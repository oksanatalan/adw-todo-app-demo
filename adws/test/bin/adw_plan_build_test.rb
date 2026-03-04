# frozen_string_literal: true

require_relative "../test_helper"
load File.expand_path("../../bin/adw_plan_build", __dir__)

class ClassifyIssueTest < Minitest::Test
  include TestHelpers

  def setup
    @issue = build_github_issue
    @logger = mock_logger
    @issue_number = 42
    @adw_id = "test1234"
  end

  def test_returns_feature_command_when_agent_returns_feature
    response = build_agent_response(output: "/feature", success: true)
    Adw::Agent.stubs(:execute_template).returns(response)

    result, error = Adw::Pipelines::PlanBuild.classify_issue(@issue, @issue_number, @adw_id, @logger)

    assert_equal "/feature", result
    assert_nil error
  end

  def test_returns_bug_command_when_agent_returns_bug
    response = build_agent_response(output: "/bug", success: true)
    Adw::Agent.stubs(:execute_template).returns(response)

    result, error = Adw::Pipelines::PlanBuild.classify_issue(@issue, @issue_number, @adw_id, @logger)

    assert_equal "/bug", result
    assert_nil error
  end

  def test_returns_chore_command_when_agent_returns_chore
    response = build_agent_response(output: "/chore", success: true)
    Adw::Agent.stubs(:execute_template).returns(response)

    result, error = Adw::Pipelines::PlanBuild.classify_issue(@issue, @issue_number, @adw_id, @logger)

    assert_equal "/chore", result
    assert_nil error
  end

  def test_returns_nil_with_error_when_agent_returns_none
    response = build_agent_response(output: "none", success: true)
    Adw::Agent.stubs(:execute_template).returns(response)

    result, error = Adw::Pipelines::PlanBuild.classify_issue(@issue, @issue_number, @adw_id, @logger)

    assert_nil result
    assert_match(/No command selected/, error)
  end

  def test_returns_nil_with_error_when_agent_returns_invalid_command
    response = build_agent_response(output: "/invalid", success: true)
    Adw::Agent.stubs(:execute_template).returns(response)

    result, error = Adw::Pipelines::PlanBuild.classify_issue(@issue, @issue_number, @adw_id, @logger)

    assert_nil result
    assert_match(/Invalid command selected/, error)
  end

  def test_returns_nil_with_error_when_agent_fails
    response = build_agent_response(output: "Agent execution failed", success: false)
    Adw::Agent.stubs(:execute_template).returns(response)

    result, error = Adw::Pipelines::PlanBuild.classify_issue(@issue, @issue_number, @adw_id, @logger)

    assert_nil result
    assert_equal "Agent execution failed", error
  end

  def test_strips_whitespace_from_agent_output
    response = build_agent_response(output: "  /feature  \n", success: true)
    Adw::Agent.stubs(:execute_template).returns(response)

    result, error = Adw::Pipelines::PlanBuild.classify_issue(@issue, @issue_number, @adw_id, @logger)

    assert_equal "/feature", result
    assert_nil error
  end

  def test_creates_request_with_correct_agent_name
    response = build_agent_response(output: "/feature", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.agent_name == "issue_classifier"
    }.returns(response)

    Adw::Pipelines::PlanBuild.classify_issue(@issue, @issue_number, @adw_id, @logger)
  end

  def test_creates_request_with_correct_slash_command
    response = build_agent_response(output: "/feature", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.slash_command == "/adw:classify_issue"
    }.returns(response)

    Adw::Pipelines::PlanBuild.classify_issue(@issue, @issue_number, @adw_id, @logger)
  end

  def test_creates_request_with_sonnet_model
    response = build_agent_response(output: "/feature", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.model == "sonnet"
    }.returns(response)

    Adw::Pipelines::PlanBuild.classify_issue(@issue, @issue_number, @adw_id, @logger)
  end
end

class BuildPlanTest < Minitest::Test
  include TestHelpers

  def setup
    @issue = build_github_issue
    @logger = mock_logger
    @issue_number = 42
    @adw_id = "test1234"
    @plan_path = ".issues/42/plan.md"
  end

  def test_creates_request_with_classification_command_as_slash_command
    response = build_agent_response(output: "Plan content", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.slash_command == "/feature"
    }.returns(response)

    Adw::Pipelines::PlanBuild.build_plan(@issue, "/feature", @plan_path, @issue_number, @adw_id, @logger)
  end

  def test_creates_request_with_opus_model
    response = build_agent_response(output: "Plan content", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.model == "opus"
    }.returns(response)

    Adw::Pipelines::PlanBuild.build_plan(@issue, "/feature", @plan_path, @issue_number, @adw_id, @logger)
  end

  def test_passes_plan_path_in_args
    response = build_agent_response(output: "Plan content", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.args.include?(@plan_path)
    }.returns(response)

    Adw::Pipelines::PlanBuild.build_plan(@issue, "/feature", @plan_path, @issue_number, @adw_id, @logger)
  end

  def test_passes_issue_data_in_args
    response = build_agent_response(output: "Plan content", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.args.any? { |arg| arg.include?(@issue.title) && arg.include?(@issue.body) }
    }.returns(response)

    Adw::Pipelines::PlanBuild.build_plan(@issue, "/feature", @plan_path, @issue_number, @adw_id, @logger)
  end

  def test_uses_planner_agent_name
    response = build_agent_response(output: "Plan content", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.agent_name == "sdlc_planner"
    }.returns(response)

    Adw::Pipelines::PlanBuild.build_plan(@issue, "/feature", @plan_path, @issue_number, @adw_id, @logger)
  end

  def test_returns_agent_response
    response = build_agent_response(output: "Plan content", success: true)
    Adw::Agent.stubs(:execute_template).returns(response)

    result = Adw::Pipelines::PlanBuild.build_plan(@issue, "/feature", @plan_path, @issue_number, @adw_id, @logger)

    assert_equal response, result
  end
end

class ImplementPlanTest < Minitest::Test
  include TestHelpers

  def setup
    @logger = mock_logger
    @issue_number = 42
    @adw_id = "test1234"
    @plan_file = ".issues/42/plan.md"
  end

  def test_creates_request_with_implement_slash_command
    response = build_agent_response(output: "Implementation done", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.slash_command == "/implement"
    }.returns(response)

    Adw::Pipelines::PlanBuild.implement_plan(@plan_file, @issue_number, @adw_id, @logger)
  end

  def test_passes_plan_file_in_args
    response = build_agent_response(output: "Implementation done", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.args.include?(@plan_file)
    }.returns(response)

    Adw::Pipelines::PlanBuild.implement_plan(@plan_file, @issue_number, @adw_id, @logger)
  end

  def test_uses_implementor_agent_name
    response = build_agent_response(output: "Implementation done", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.agent_name == "sdlc_implementor"
    }.returns(response)

    Adw::Pipelines::PlanBuild.implement_plan(@plan_file, @issue_number, @adw_id, @logger)
  end

  def test_uses_sonnet_model
    response = build_agent_response(output: "Implementation done", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.model == "sonnet"
    }.returns(response)

    Adw::Pipelines::PlanBuild.implement_plan(@plan_file, @issue_number, @adw_id, @logger)
  end

  def test_returns_agent_response
    response = build_agent_response(output: "Implementation done", success: true)
    Adw::Agent.stubs(:execute_template).returns(response)

    result = Adw::Pipelines::PlanBuild.implement_plan(@plan_file, @issue_number, @adw_id, @logger)

    assert_equal response, result
  end
end

class GitBranchTest < Minitest::Test
  include TestHelpers

  def setup
    @issue = build_github_issue
    @logger = mock_logger
    @issue_number = 42
    @adw_id = "test1234"
  end

  def test_returns_branch_name_on_success
    response = build_agent_response(output: "feature/42-test-branch", success: true)
    Adw::Agent.stubs(:execute_template).returns(response)

    branch_name, error = Adw::Pipelines::PlanBuild.git_branch(@issue, "/feature", @issue_number, @adw_id, @logger)

    assert_equal "feature/42-test-branch", branch_name
    assert_nil error
  end

  def test_returns_nil_with_error_on_failure
    response = build_agent_response(output: "Branch creation failed", success: false)
    Adw::Agent.stubs(:execute_template).returns(response)

    branch_name, error = Adw::Pipelines::PlanBuild.git_branch(@issue, "/feature", @issue_number, @adw_id, @logger)

    assert_nil branch_name
    assert_equal "Branch creation failed", error
  end

  def test_strips_whitespace_from_branch_name
    response = build_agent_response(output: "  feature/42-test-branch  \n", success: true)
    Adw::Agent.stubs(:execute_template).returns(response)

    branch_name, _error = Adw::Pipelines::PlanBuild.git_branch(@issue, "/feature", @issue_number, @adw_id, @logger)

    assert_equal "feature/42-test-branch", branch_name
  end

  def test_passes_issue_type_without_slash_prefix_in_args
    response = build_agent_response(output: "feature/42-test-branch", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.args.include?("feature")
    }.returns(response)

    Adw::Pipelines::PlanBuild.git_branch(@issue, "/feature", @issue_number, @adw_id, @logger)
  end

  def test_uses_branch_generator_agent_name
    response = build_agent_response(output: "feature/42-test-branch", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.agent_name == "branch_generator"
    }.returns(response)

    Adw::Pipelines::PlanBuild.git_branch(@issue, "/feature", @issue_number, @adw_id, @logger)
  end

  def test_uses_generate_branch_name_slash_command
    response = build_agent_response(output: "feature/42-test-branch", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.slash_command == "/adw:generate_branch_name"
    }.returns(response)

    Adw::Pipelines::PlanBuild.git_branch(@issue, "/feature", @issue_number, @adw_id, @logger)
  end
end

class GitCommitTest < Minitest::Test
  include TestHelpers

  def setup
    @issue = build_github_issue
    @logger = mock_logger
    @issue_number = 42
    @adw_id = "test1234"
  end

  def test_agent_name_includes_committer_suffix
    response = build_agent_response(output: "commit abc123", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.agent_name == "sdlc_implementor_committer"
    }.returns(response)

    Adw::Pipelines::PlanBuild.git_commit("sdlc_implementor", @issue, "/feature", @issue_number, @adw_id, @logger)
  end

  def test_commit_message_includes_issue_type
    response = build_agent_response(output: "commit abc123", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.args.any? { |arg| arg.include?("feature") }
    }.returns(response)

    Adw::Pipelines::PlanBuild.git_commit("sdlc_implementor", @issue, "/feature", @issue_number, @adw_id, @logger)
  end

  def test_commit_message_includes_issue_number
    response = build_agent_response(output: "commit abc123", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.args.any? { |arg| arg.include?("#42") }
    }.returns(response)

    Adw::Pipelines::PlanBuild.git_commit("sdlc_implementor", @issue, "/feature", @issue_number, @adw_id, @logger)
  end

  def test_returns_commit_message_on_success
    response = build_agent_response(output: "commit abc123", success: true)
    Adw::Agent.stubs(:execute_template).returns(response)

    commit_msg, error = Adw::Pipelines::PlanBuild.git_commit("sdlc_implementor", @issue, "/feature", @issue_number, @adw_id, @logger)

    assert_equal "commit abc123", commit_msg
    assert_nil error
  end

  def test_returns_nil_with_error_on_failure
    response = build_agent_response(output: "Commit failed", success: false)
    Adw::Agent.stubs(:execute_template).returns(response)

    commit_msg, error = Adw::Pipelines::PlanBuild.git_commit("sdlc_implementor", @issue, "/feature", @issue_number, @adw_id, @logger)

    assert_nil commit_msg
    assert_equal "Commit failed", error
  end

  def test_uses_git_commit_slash_command
    response = build_agent_response(output: "commit abc123", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.slash_command == "/git:commit"
    }.returns(response)

    Adw::Pipelines::PlanBuild.git_commit("sdlc_implementor", @issue, "/feature", @issue_number, @adw_id, @logger)
  end
end

class PullRequestTest < Minitest::Test
  include TestHelpers

  def setup
    @issue = build_github_issue
    @logger = mock_logger
    @issue_number = 42
    @adw_id = "test1234"
    @branch_name = "feature/42-test-branch"
  end

  def test_args_include_branch_name
    response = build_agent_response(output: "https://github.com/test/repo/pull/1", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.args.include?(@branch_name)
    }.returns(response)

    Adw::Pipelines::PlanBuild.pull_request(@branch_name, @issue, @issue_number, @adw_id, @logger)
  end

  def test_args_include_issue_json
    response = build_agent_response(output: "https://github.com/test/repo/pull/1", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.args.include?(@issue.to_json)
    }.returns(response)

    Adw::Pipelines::PlanBuild.pull_request(@branch_name, @issue, @issue_number, @adw_id, @logger)
  end

  def test_args_include_adw_id
    response = build_agent_response(output: "https://github.com/test/repo/pull/1", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.args.include?(@adw_id)
    }.returns(response)

    Adw::Pipelines::PlanBuild.pull_request(@branch_name, @issue, @issue_number, @adw_id, @logger)
  end

  def test_returns_pr_url_on_success
    response = build_agent_response(output: "https://github.com/test/repo/pull/1", success: true)
    Adw::Agent.stubs(:execute_template).returns(response)

    pr_url, error = Adw::Pipelines::PlanBuild.pull_request(@branch_name, @issue, @issue_number, @adw_id, @logger)

    assert_equal "https://github.com/test/repo/pull/1", pr_url
    assert_nil error
  end

  def test_returns_nil_with_error_on_failure
    response = build_agent_response(output: "PR creation failed", success: false)
    Adw::Agent.stubs(:execute_template).returns(response)

    pr_url, error = Adw::Pipelines::PlanBuild.pull_request(@branch_name, @issue, @issue_number, @adw_id, @logger)

    assert_nil pr_url
    assert_equal "PR creation failed", error
  end

  def test_uses_pr_creator_agent_name
    response = build_agent_response(output: "https://github.com/test/repo/pull/1", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.agent_name == "pr_creator"
    }.returns(response)

    Adw::Pipelines::PlanBuild.pull_request(@branch_name, @issue, @issue_number, @adw_id, @logger)
  end

  def test_uses_pull_request_slash_command
    response = build_agent_response(output: "https://github.com/test/repo/pull/1", success: true)
    Adw::Agent.expects(:execute_template).with { |req|
      req.slash_command == "/adw:pull_request"
    }.returns(response)

    Adw::Pipelines::PlanBuild.pull_request(@branch_name, @issue, @issue_number, @adw_id, @logger)
  end
end

class MainFlowTest < Minitest::Test
  include TestHelpers

  def setup
    @issue = build_github_issue
    @logger = mock_logger
    @adw_id = "test1234"
    @issue_number = "42"
    @tracker = build_tracker
    @plan_path = Adw::PipelineHelpers.plan_path_for(@issue_number)

    # Stub ARGV for parse_args
    @original_argv = ARGV.dup
    ARGV.replace([@issue_number, @adw_id])

    # Stub utility methods
    Adw::Utils.stubs(:make_adw_id).returns(@adw_id)
    Adw::Utils.stubs(:setup_logger).returns(@logger)

    # Stub GitHub methods
    Adw::GitHub.stubs(:repo_url).returns("https://github.com/test/repo.git")
    Adw::GitHub.stubs(:extract_repo_path).returns("test/repo")
    Adw::GitHub.stubs(:fetch_issue).returns(@issue)
    Adw::GitHub.stubs(:create_issue_comment).returns("comment-123")

    # Stub Tracker methods
    Adw::Tracker.stubs(:load).returns(@tracker)
    Adw::Tracker.stubs(:update)
    Adw::Tracker.stubs(:set_phase_comment)
    Adw::Tracker.stubs(:save)

    # Stub file reading for post_plan_comment
    File.stubs(:read).with(@plan_path).returns("# Plan content")
  end

  def teardown
    ARGV.replace(@original_argv)
  end

  def test_happy_path_completes_without_error
    stub_agent_sequence(
      build_agent_response(output: "/feature", success: true),
      build_agent_response(output: "feature/42-test-branch", success: true),
      build_agent_response(output: "Plan created", success: true),
      build_agent_response(output: "Implementation done", success: true)
    )

    # Should not raise
    Adw::Pipelines::PlanBuild.main
  end

  def test_happy_path_updates_tracker_status_through_phases
    stub_agent_sequence(
      build_agent_response(output: "/feature", success: true),
      build_agent_response(output: "feature/42-test-branch", success: true),
      build_agent_response(output: "Plan created", success: true),
      build_agent_response(output: "Implementation done", success: true)
    )

    # Expect tracker updates for classifying, planning, implementing
    Adw::Tracker.expects(:update).with(anything, @issue_number, "classifying", @logger).once
    Adw::Tracker.expects(:update).with(anything, @issue_number, "planning", @logger).once
    Adw::Tracker.expects(:update).with(anything, @issue_number, "implementing", @logger).once

    Adw::Pipelines::PlanBuild.main
  end

  def test_classify_failure_exits_with_error
    classify_response = build_agent_response(output: "Classification failed", success: false)
    Adw::Agent.stubs(:execute_template).returns(classify_response)

    # check_error calls exit 1 when there's an error
    Adw::Tracker.expects(:update).with(anything, @issue_number, "classifying", @logger).once
    Adw::Tracker.expects(:update).with(anything, @issue_number, "error", @logger).once

    assert_raises(SystemExit) do
      Adw::Pipelines::PlanBuild.main
    end
  end

  def test_branch_failure_exits_with_error
    stub_agent_sequence(
      build_agent_response(output: "/feature", success: true),
      build_agent_response(output: "Branch failed", success: false)
    )

    Adw::Tracker.expects(:update).with(anything, @issue_number, "error", @logger).once

    assert_raises(SystemExit) do
      Adw::Pipelines::PlanBuild.main
    end
  end

  def test_plan_failure_exits_with_error
    stub_agent_sequence(
      build_agent_response(output: "/feature", success: true),
      build_agent_response(output: "feature/42-test-branch", success: true),
      build_agent_response(output: "Plan failed", success: false)
    )

    Adw::Tracker.expects(:update).with(anything, @issue_number, "error", @logger).once

    assert_raises(SystemExit) do
      Adw::Pipelines::PlanBuild.main
    end
  end

  def test_implement_failure_exits_with_error
    stub_agent_sequence(
      build_agent_response(output: "/feature", success: true),
      build_agent_response(output: "feature/42-test-branch", success: true),
      build_agent_response(output: "Plan created", success: true),
      build_agent_response(output: "Implementation failed", success: false)
    )

    Adw::Tracker.expects(:update).with(anything, @issue_number, "error", @logger).once

    assert_raises(SystemExit) do
      Adw::Pipelines::PlanBuild.main
    end
  end

  def test_saves_tracker_after_posting_plan_comment
    stub_agent_sequence(
      build_agent_response(output: "/feature", success: true),
      build_agent_response(output: "feature/42-test-branch", success: true),
      build_agent_response(output: "Plan created", success: true),
      build_agent_response(output: "Implementation done", success: true)
    )

    Adw::Tracker.expects(:set_phase_comment).with(anything, "plan", "comment-123").once
    Adw::Tracker.expects(:save).with(@issue_number, anything).at_least_once

    Adw::Pipelines::PlanBuild.main
  end

  def test_sets_classification_on_tracker
    stub_agent_sequence(
      build_agent_response(output: "/bug", success: true),
      build_agent_response(output: "bug/42-fix-branch", success: true),
      build_agent_response(output: "Plan created", success: true),
      build_agent_response(output: "Implementation done", success: true)
    )

    Adw::Pipelines::PlanBuild.main

    assert_equal "/bug", @tracker[:classification]
  end

  def test_sets_branch_name_on_tracker
    stub_agent_sequence(
      build_agent_response(output: "/feature", success: true),
      build_agent_response(output: "feature/42-test-branch", success: true),
      build_agent_response(output: "Plan created", success: true),
      build_agent_response(output: "Implementation done", success: true)
    )

    Adw::Pipelines::PlanBuild.main

    assert_equal "feature/42-test-branch", @tracker[:branch_name]
  end

  private

  # Stubs Agent.execute_template to return responses in sequence
  def stub_agent_sequence(*responses)
    Adw::Agent.stubs(:execute_template).returns(*responses)
  end
end
