# frozen_string_literal: true

require_relative "../../../test_helper"

class CreateWorktreeTest < Minitest::Test
  include TestFactories

  def setup
    @issue_number = 42
    @adw_id = "abc12345"
    @logger = build_logger
    @branch_name = "feat-42-abc12345-add-login"
    @issue = build_issue(number: @issue_number)
    @tracker = build_tracker

    Adw::Tracker.stubs(:update)
    Adw::Tracker.stubs(:save)
  end

  def test_generates_branch_and_creates_worktree
    # First call generates branch name, second call creates worktree
    Adw::Agent.stubs(:execute_template)
      .returns(build_agent_response(output: @branch_name, success: true))
      .then
      .returns(build_agent_response(output: "/abs/path/trees/#{@branch_name}", success: true))

    result = Adw::Actors::CreateWorktree.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      issue: @issue,
      issue_command: "/feature",
      tracker: @tracker
    )

    assert result.success?
    assert_equal @branch_name, result.branch_name
    assert result.worktree_path.end_with?(@branch_name)
    assert_equal @branch_name, result.tracker[:branch_name]
    assert result.tracker[:worktree_path].end_with?(@branch_name)
  end

  def test_fails_when_branch_generation_fails
    Adw::Agent.stubs(:execute_template).returns(build_agent_response(output: "git error", success: false))

    result = Adw::Actors::CreateWorktree.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      issue: @issue,
      issue_command: "/feature",
      tracker: @tracker
    )

    refute result.success?
    assert_match(/Branch name generation failed/, result.error)
  end

  def test_fails_when_worktree_creation_fails
    Adw::Agent.stubs(:execute_template)
      .returns(build_agent_response(output: @branch_name, success: true))
      .then
      .returns(build_agent_response(output: "git worktree error", success: false))

    result = Adw::Actors::CreateWorktree.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      issue: @issue,
      issue_command: "/feature",
      tracker: @tracker
    )

    refute result.success?
    assert_match(/Worktree creation failed/, result.error)
  end
end
