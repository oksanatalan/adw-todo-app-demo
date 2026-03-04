# frozen_string_literal: true

require_relative "../test_helper"

class AdwPlanBuildTestTest < Minitest::Test
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
    Adw::PipelineHelpers.stubs(:plan_path_for).returns(File.join(Adw.project_root, ".issues", "42", "plan.md"))
    Open3.stubs(:capture3).with("git", "checkout", anything).returns(["", "", FakeProcessStatus.new(true)])
    Open3.stubs(:capture3).with("git", "push", "--set-upstream", "origin", anything).returns(["", "", FakeProcessStatus.new(true)])
    Open3.stubs(:capture3).with("git", "rev-parse", "--abbrev-ref", "HEAD").returns(["main\n", "", FakeProcessStatus.new(true)])
    # git push for PushBranch actor
    Open3.stubs(:capture3).with("git", "push", "origin", anything).returns(["", "", FakeProcessStatus.new(true)])
    # git status for CommitChanges actor
    Open3.stubs(:capture3).with("git", "status", "--porcelain").returns(["", "", FakeProcessStatus.new(true)])
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

  def failing_test_json
    JSON.generate([{ "test_name" => "test_something", "passed" => false,
                     "execution_command" => "ruby -e 'raise'", "test_purpose" => "test", "error" => "assertion failed" }])
  end

  # Happy path: plan+build+test+commit+push+done all succeed
  # Agent calls: 1) classify, 2) branch, 3) build plan, 4) implement, 5) run tests
  # (PublishPlan reads a file - no agent call; git status returns empty so no commit agent)
  def test_happy_path_returns_success
    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "/feature"),          # 1. classify
      success_response(output: "feature/issue-42"),  # 2. branch
      success_response(output: "plan created"),       # 3. build plan
      success_response(output: "implemented"),        # 4. implement plan
      success_response(output: passing_test_json)    # 5. run tests
    )

    result = Adw::Workflows::PlanBuildTest.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    assert result.success?, "Expected success but got error: #{result.error}"
  end

  # Early exit when classification fails
  def test_fails_when_classification_fails
    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "none")  # none classification
    )

    result = Adw::Workflows::PlanBuildTest.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    refute result.success?
  end

  # Fails when issue cannot be fetched
  def test_fails_when_issue_cannot_be_fetched
    Adw::GitHub.stubs(:fetch_issue).returns(nil)

    result = Adw::Workflows::PlanBuildTest.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    refute result.success?
    assert_match(/Could not fetch issue/, result.error)
  end

  # Propagates failure when tests fail
  # Agent calls: 1) classify, 2) branch, 3) build plan, 4) implement,
  # then test loop: test+resolver until max retries (MAX_TEST_RETRY_ATTEMPTS=4)
  def test_fails_when_tests_fail
    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "/feature"),          # 1. classify
      success_response(output: "feature/issue-42"),  # 2. branch
      success_response(output: "plan created"),       # 3. build plan
      success_response(output: "implemented"),        # 4. implement plan
      # Test loop: 4 attempts with resolvers in between
      success_response(output: failing_test_json),   # 5. test attempt 1
      success_response(output: "resolved"),           # 6. resolver attempt 1
      success_response(output: failing_test_json),   # 7. test attempt 2
      success_response(output: "resolved"),           # 8. resolver attempt 2
      success_response(output: failing_test_json),   # 9. test attempt 3
      success_response(output: "resolved"),           # 10. resolver attempt 3
      success_response(output: failing_test_json)    # 11. test attempt 4
    )

    result = Adw::Workflows::PlanBuildTest.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    refute result.success?
    assert_match(/tests failed/, result.error)
  end

  # Fails when push fails
  def test_fails_when_push_fails
    Open3.stubs(:capture3).with("git", "push", "origin", anything).returns(["", "not allowed", FakeProcessStatus.new(false)])

    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "/feature"),          # 1. classify
      success_response(output: "feature/issue-42"),  # 2. branch
      success_response(output: "plan created"),       # 3. build plan
      success_response(output: "implemented"),        # 4. implement plan
      success_response(output: passing_test_json)    # 5. run tests
    )

    result = Adw::Workflows::PlanBuildTest.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    refute result.success?
    assert_match(/push failed|Git push failed/, result.error)
  end
end
