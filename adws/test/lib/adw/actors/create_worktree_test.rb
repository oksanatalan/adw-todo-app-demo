# frozen_string_literal: true

require_relative "../../../test_helper"

class CreateWorktreeTest < Minitest::Test
  include TestFactories

  def setup
    @issue_number = 42
    @adw_id = "abc12345"
    @logger = build_logger
    @branch_name = "feature-42-abc12345-test-issue"
    @worktree_path = "/abs/path/trees/#{@branch_name}"
    @issue = build_issue(number: @issue_number)
    @tracker = build_tracker

    Adw::Tracker.stubs(:update)
    Adw::Tracker.stubs(:save)
    Adw::BranchName.stubs(:generate).returns(@branch_name)
  end

  def test_generates_branch_and_creates_worktree
    Open3.stubs(:capture3).returns(["#{@worktree_path}\n", "", mock_success_status])

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
    assert_equal @worktree_path, result.worktree_path
    assert_equal @branch_name, result.tracker[:branch_name]
    assert_equal @worktree_path, result.tracker[:worktree_path]
  end

  def test_fails_when_worktree_creation_fails
    Open3.stubs(:capture3).returns(["", "git worktree error", mock_failure_status])

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

  def test_calls_branch_name_generate_with_correct_args
    Adw::BranchName.expects(:generate).with("feature", @issue_number, @adw_id, "Test Issue").returns(@branch_name)
    Open3.stubs(:capture3).returns(["#{@worktree_path}\n", "", mock_success_status])

    Adw::Actors::CreateWorktree.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      issue: @issue,
      issue_command: "/feature",
      tracker: @tracker
    )
  end

  private

  def mock_success_status
    status = mock("status")
    status.stubs(:success?).returns(true)
    status
  end

  def mock_failure_status
    status = mock("status")
    status.stubs(:success?).returns(false)
    status
  end
end
