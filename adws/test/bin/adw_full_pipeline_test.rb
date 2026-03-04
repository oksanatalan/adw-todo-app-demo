# frozen_string_literal: true

require_relative "../test_helper"

class AdwFullPipelineTest < Minitest::Test
  include TestFactories

  def setup
    @issue_number = "42"
    @adw_id = "abc12345"
    @logger = build_logger

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
    Adw::PipelineHelpers.stubs(:plan_path_for).returns(".issues/42/plan.md")
    Adw::PipelineHelpers.stubs(:parse_issue_review_results).returns({
      success: true, screenshots: [], review_issues: []
    })
    Adw::PipelineHelpers.stubs(:format_evidence_comment).returns("evidence comment")
    Adw::PipelineHelpers.stubs(:link_screenshot_urls)
    Adw::R2.stubs(:upload_evidence).returns([])

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
  # Agent calls: 1) classify, 2) branch, 3) create worktree, 4) configure worktree,
  # 5) start worktree env, 6) build plan, 7) implement, 8) tests, 9) review code,
  # 10) review issue (non-blocking), 11) docs (non-blocking), 12) PR
  def test_happy_path_returns_success
    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "/feature"),                               # 1. classify
      success_response(output: "feature/issue-42"),                       # 2. branch
      success_response(output: "/abs/trees/feature-issue-42"),            # 3. create worktree
      success_response(output: '{"postgres_port":5500,"backend_port":8100,"frontend_port":9100,"compose_project":"adw-test"}'), # 4. configure worktree
      success_response(output: "services started"),                       # 5. start worktree env
      success_response(output: "plan created"),                           # 6. build plan
      success_response(output: "implemented"),                            # 7. implement plan
      success_response(output: passing_test_json),                       # 8. run tests
      success_response(output: ok_review_json),                          # 9. review code
      success_response(output: "visual review ok"),                      # 10. review issue (non-blocking)
      success_response(output: "docs generated"),                        # 11. generate docs (non-blocking)
      success_response(output: "https://github.com/test/repo/pull/1")   # 12. PR
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
      success_response(output: "feature/issue-42"),  # 2. branch
      success_response(output: "/abs/trees/feat"),   # 3. create worktree
      success_response(output: '{"postgres_port":5500,"backend_port":8100,"frontend_port":9100,"compose_project":"adw-test"}'), # 4. configure worktree
      success_response(output: "services started"),  # 5. start worktree env
      success_response(output: "plan created"),      # 6. build plan
      success_response(output: "implemented"),       # 7. implement plan
      # Test attempts (MAX_TEST_RETRY_ATTEMPTS = 4) with resolvers in between
      success_response(output: failing_test_json),  # 8. test attempt 1
      success_response(output: "resolved"),          # 9. resolver
      success_response(output: failing_test_json),  # 10. test attempt 2
      success_response(output: "resolved"),          # 11. resolver
      success_response(output: failing_test_json),  # 12. test attempt 3
      success_response(output: "resolved"),          # 13. resolver
      success_response(output: failing_test_json)   # 14. test attempt 4
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
      success_response(output: "feature/issue-42"),   # 2. branch
      success_response(output: "/abs/trees/feat"),    # 3. create worktree
      success_response(output: '{"postgres_port":5500,"backend_port":8100,"frontend_port":9100,"compose_project":"adw-test"}'), # 4. configure worktree
      success_response(output: "services started"),   # 5. start worktree env
      success_response(output: "plan created"),       # 6. build plan
      success_response(output: "implemented"),        # 7. implement plan
      success_response(output: passing_test_json),   # 8. tests pass
      success_response(output: critical_review_json), # 9. review: critical
      success_response(output: "resolver attempt"),   # 10. fix attempt 1
      success_response(output: critical_review_json), # 11. recheck: still critical
      success_response(output: "resolver attempt"),   # 12. fix attempt 2
      success_response(output: critical_review_json) # 13. recheck: still critical
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
      success_response(output: "feature/issue-42"),  # 2. branch
      success_response(output: "/abs/trees/feat"),   # 3. create worktree
      success_response(output: '{"postgres_port":5500,"backend_port":8100,"frontend_port":9100,"compose_project":"adw-test"}'), # 4. configure worktree
      success_response(output: "services started"),  # 5. start worktree env
      success_response(output: "plan created"),      # 6. build plan
      success_response(output: "implemented"),       # 7. implement plan
      success_response(output: passing_test_json),  # 8. tests pass
      success_response(output: ok_review_json),     # 9. review ok
      success_response(output: "visual ok"),         # 10. visual review (non-blocking)
      success_response(output: "docs ok"),           # 11. docs (non-blocking)
      failure_response(output: "gh error")           # 12. PR fails
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
      success_response(output: "feature/issue-42"),                     # 2. branch
      success_response(output: "/abs/trees/feat"),                      # 3. create worktree
      success_response(output: '{"postgres_port":5500,"backend_port":8100,"frontend_port":9100,"compose_project":"adw-test"}'), # 4. configure worktree
      success_response(output: "services started"),                     # 5. start worktree env
      success_response(output: "plan created"),                         # 6. build plan
      success_response(output: "implemented"),                          # 7. implement plan
      success_response(output: passing_test_json),                     # 8. tests pass
      success_response(output: ok_review_json),                        # 9. review ok
      failure_response(output: "playwright error"),                     # 10. visual review fails (non-blocking)
      success_response(output: "docs ok"),                             # 11. docs (non-blocking)
      success_response(output: "https://github.com/test/repo/pull/1") # 12. PR
    )

    result = Adw::Workflows::FullPipeline.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    assert result.success?, "Expected success even when visual review fails, got error: #{result.error}"
  end
end
