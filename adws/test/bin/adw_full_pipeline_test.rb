# frozen_string_literal: true

require_relative "../test_helper"

class AdwFullPipelineTest < Minitest::Test
  include TestFactories

  def setup
    @issue_number = "42"
    @adw_id = "abc12345"
    @logger = build_logger
    @branch_name = "feature-42-abc12345-test-issue"
    @worktree_path = "/abs/trees/#{@branch_name}"

    # Stub external I/O
    Adw::GitHub.stubs(:repo_url).returns("https://github.com/test/repo")
    Adw::GitHub.stubs(:extract_repo_path).returns("test/repo")
    Adw::GitHub.stubs(:fetch_issue).returns(build_issue(number: 42))
    Adw::GitHub.stubs(:create_issue_comment).returns("123")
    Adw::GitHub.stubs(:update_issue_comment)
    Adw::GitHub.stubs(:transition_label)
    Adw::Tracker.stubs(:load).returns(nil)
    Adw::Tracker.stubs(:update)
    Adw::Tracker.stubs(:save)
    Adw::Tracker.stubs(:set_phase_comment)
    Adw::PipelineHelpers.stubs(:plan_path_for).returns(File.join(Adw.project_root, ".issues", "42", "plan.md"))
    Adw::PipelineHelpers.stubs(:parse_issue_review_results).returns({
      success: true, screenshots: [], review_issues: []
    })
    Adw::PipelineHelpers.stubs(:format_evidence_comment).returns("evidence comment")
    Adw::PipelineHelpers.stubs(:link_screenshot_urls)
    Adw::R2.stubs(:upload_evidence).returns([])

    # Branch name generation (deterministic Ruby method)
    Adw::BranchName.stubs(:generate).returns(@branch_name)

    # Worktree script stubs
    script_base = File.join(Adw.project_root, "adws", "bin")
    Open3.stubs(:capture3).with("#{script_base}/worktree_create", @branch_name)
      .returns(["#{@worktree_path}\n", "", FakeProcessStatus.new(true)])
    Open3.stubs(:capture3).with("#{script_base}/worktree/isolate", @worktree_path)
      .returns(['{"postgres_port":5500,"backend_port":8100,"frontend_port":9100,"compose_project":"adw-test"}', "", FakeProcessStatus.new(true)])
    Open3.stubs(:capture3).with("#{script_base}/worktree/setup", @worktree_path)
      .returns(["", "", FakeProcessStatus.new(true)])
    Open3.stubs(:capture3).with("#{script_base}/worktree/start", @worktree_path)
      .returns(["", "", FakeProcessStatus.new(true)])

    # git commands (full_pipeline uses worktree, so chdir: is always present)
    Open3.stubs(:capture3).with("git", "status", "--porcelain", chdir: anything).returns(["", "", FakeProcessStatus.new(true)])
    Open3.stubs(:capture3).with("git", "push", "origin", anything, chdir: anything).returns(["", "", FakeProcessStatus.new(true)])
  end

  def success_response(output: "done")
    build_agent_response(output: output, success: true)
  end

  def failure_response(output: "agent error")
    build_agent_response(output: output, success: false)
  end

  def passing_test_json
    JSON.generate([{ "test_name" => "test_something", "passed" => true,
                     "execution_command" => "ruby -e 'puts 1'", "test_purpose" => "test", "error" => nil }])
  end

  def ok_review_json
    JSON.generate({
      "overall_severity" => "low",
      "summary" => "Code looks good",
      "checks" => [],
      "action_required" => "none",
      "fix_suggestions" => []
    })
  end

  # Happy path: all stages succeed
  # Agent calls: 1) classify, 2) build plan, 3) implement, 4) tests, 5) review code,
  # 6) review issue (non-blocking), 7) docs (non-blocking), 8) PR
  # Worktree calls handled by script stubs in setup
  def test_happy_path_returns_success
    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "/feature"),                               # 1. classify
      success_response(output: "plan created"),                           # 2. build plan
      success_response(output: "implemented"),                            # 3. implement plan
      success_response(output: passing_test_json),                       # 4. run tests
      success_response(output: ok_review_json),                          # 5. review code
      success_response(output: "visual review ok"),                      # 6. review issue (non-blocking)
      success_response(output: "docs generated"),                        # 7. generate docs (non-blocking)
      success_response(output: "https://github.com/test/repo/pull/1")   # 8. PR
    )

    result = Adw::Workflows::FullPipeline.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    assert result.success?, "Expected success but got error: #{result.error}"
  end

  # Early exit when issue cannot be fetched
  def test_fails_when_issue_cannot_be_fetched
    Adw::GitHub.stubs(:fetch_issue).returns(nil)

    result = Adw::Workflows::FullPipeline.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    refute result.success?
    assert_match(/Could not fetch issue/, result.error)
  end

  # Early exit when classification returns none
  def test_fails_when_classification_is_none
    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "none")
    )

    result = Adw::Workflows::FullPipeline.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    refute result.success?
  end

  # Tests failing stops the pipeline
  def test_fails_when_tests_fail_after_max_retries
    failing_test_json = JSON.generate([{
      "test_name" => "test_something", "passed" => false,
      "execution_command" => "ruby -e 'raise'", "test_purpose" => "test", "error" => "assertion failed"
    }])

    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "/feature"),          # 1. classify
      success_response(output: "plan created"),      # 2. build plan
      success_response(output: "implemented"),       # 3. implement plan
      # Test attempts (MAX_TEST_RETRY_ATTEMPTS = 4) with resolvers in between
      success_response(output: failing_test_json),  # 4. test attempt 1
      success_response(output: "resolved"),          # 5. resolver
      success_response(output: failing_test_json),  # 6. test attempt 2
      success_response(output: "resolved"),          # 7. resolver
      success_response(output: failing_test_json),  # 8. test attempt 3
      success_response(output: "resolved"),          # 9. resolver
      success_response(output: failing_test_json)   # 10. test attempt 4
    )

    result = Adw::Workflows::FullPipeline.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    refute result.success?
    assert_match(/tests failed/, result.error)
  end

  # Critical review issues stop the pipeline
  def test_fails_when_review_finds_critical_issues
    critical_review_json = JSON.generate({
      "overall_severity" => "critical",
      "summary" => "Security vulnerability",
      "checks" => [{ "name" => "security", "result" => "FAIL", "severity" => "critical", "details" => "SQL injection" }],
      "action_required" => "fix_and_rerun",
      "fix_suggestions" => ["Use parameterized queries"]
    })

    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "/feature"),           # 1. classify
      success_response(output: "plan created"),       # 2. build plan
      success_response(output: "implemented"),        # 3. implement plan
      success_response(output: passing_test_json),   # 4. tests pass
      success_response(output: critical_review_json), # 5. review: critical
      success_response(output: "resolver attempt"),   # 6. fix attempt 1
      success_response(output: critical_review_json), # 7. recheck: still critical
      success_response(output: "resolver attempt"),   # 8. fix attempt 2
      success_response(output: critical_review_json) # 9. recheck: still critical
    )

    result = Adw::Workflows::FullPipeline.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    refute result.success?
    assert_match(/critical|review/, result.error)
  end

  # PR creation failure stops the pipeline
  def test_fails_when_pr_creation_fails
    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "/feature"),          # 1. classify
      success_response(output: "plan created"),      # 2. build plan
      success_response(output: "implemented"),       # 3. implement plan
      success_response(output: passing_test_json),  # 4. tests pass
      success_response(output: ok_review_json),     # 5. review ok
      success_response(output: "visual ok"),         # 6. visual review (non-blocking)
      success_response(output: "docs ok"),           # 7. docs (non-blocking)
      failure_response(output: "gh error")           # 8. PR fails
    )

    result = Adw::Workflows::FullPipeline.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    refute result.success?
    assert_match(/Pull request creation failed|pr|PR/, result.error)
  end

  # Visual review failure is non-blocking — pipeline continues
  def test_visual_review_failure_is_non_blocking
    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "/feature"),                             # 1. classify
      success_response(output: "plan created"),                         # 2. build plan
      success_response(output: "implemented"),                          # 3. implement plan
      success_response(output: passing_test_json),                     # 4. tests pass
      success_response(output: ok_review_json),                        # 5. review ok
      failure_response(output: "playwright error"),                     # 6. visual review fails (non-blocking)
      success_response(output: "docs ok"),                             # 7. docs (non-blocking)
      success_response(output: "https://github.com/test/repo/pull/1") # 8. PR
    )

    result = Adw::Workflows::FullPipeline.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    assert result.success?, "Expected success even when visual review fails, got error: #{result.error}"
  end
end
