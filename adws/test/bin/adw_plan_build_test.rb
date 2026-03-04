# frozen_string_literal: true

require_relative "../test_helper"

class AdwPlanBuildTest < Minitest::Test
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
  end

  def stub_agent_responses(*responses)
    stub = Adw::Agent.stubs(:execute_template)
    responses.each { |r| stub = stub.returns(r) }
  end

  def success_response(output: "done")
    build_agent_response(output: output, success: true)
  end

  def failure_response(output: "agent error")
    build_agent_response(output: output, success: false)
  end

  # Happy path: all actors succeed
  # Agent calls: 1) classify, 2) branch name, 3) build plan, 4) implement plan
  # (PublishPlan reads a file but makes no agent call; exception is swallowed)
  def test_happy_path_returns_success
    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "/feature"),                     # 1. classify
      success_response(output: "feature/issue-42-test-issue"),  # 2. branch name
      success_response(output: "plan created"),                  # 3. build plan
      success_response(output: "implemented")                    # 4. implement plan
    )

    result = Adw::Workflows::PlanBuild.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    assert result.success?, "Expected success but got error: #{result.error}"
  end

  # Early exit when issue fetch fails
  def test_fails_when_issue_cannot_be_fetched
    Adw::GitHub.stubs(:fetch_issue).returns(nil)

    result = Adw::Workflows::PlanBuild.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    refute result.success?
    assert_match(/Could not fetch issue/, result.error)
  end

  # Early exit when issue is classified as "none"
  def test_fails_when_classification_is_none
    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "none")  # classify returns none
    )

    result = Adw::Workflows::PlanBuild.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    refute result.success?
    assert_match(/Invalid classification|classification/, result.error)
  end

  # Propagates error when plan build fails (call #3)
  def test_fails_when_plan_build_fails
    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "/feature"),          # 1. classify
      success_response(output: "feature/issue-42"),  # 2. branch
      failure_response(output: "plan build failed")  # 3. build plan fails
    )

    result = Adw::Workflows::PlanBuild.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    refute result.success?
    assert_match(/Plan build failed|plan build failed/, result.error)
  end

  # Propagates error when implementation fails (call #4, after publish_plan which is non-agent)
  def test_fails_when_implementation_fails
    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "/feature"),           # 1. classify
      success_response(output: "feature/issue-42"),   # 2. branch
      success_response(output: "plan created"),        # 3. build plan
      failure_response(output: "implementation failed") # 4. implement plan fails
    )

    result = Adw::Workflows::PlanBuild.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    refute result.success?
    assert_match(/Implementation failed|implementation failed/, result.error)
  end

  # Tracker is initialized even when no prior state exists
  def test_initializes_tracker_from_scratch
    Adw::Tracker.stubs(:load).returns(nil)
    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "/feature"),          # 1. classify
      success_response(output: "feature/issue-42"),  # 2. branch
      success_response(output: "plan created"),       # 3. build plan
      success_response(output: "implemented")         # 4. implement plan
    )

    result = Adw::Workflows::PlanBuild.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    assert result.success?
  end
end
