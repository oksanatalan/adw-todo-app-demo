# frozen_string_literal: true

require_relative "../../../test_helper"

class DestroyWorktreeTest < Minitest::Test
  include TestFactories

  def setup
    @issue_number = 42
    @adw_id = "abc12345"
    @logger = build_logger
    @worktree_path = "/abs/path/trees/feat-42-abc12345-add-login"
    @issue_tracker_data = build_issue_tracker(
      worktree_path: @worktree_path,
      backend_port: 8042,
      frontend_port: 9042,
      postgres_port: 5442,
      compose_project: "adw-test"
    )

    Adw::Tracker.stubs(:update)
    Adw::Tracker.stubs(:save)
    Adw::Tracker::Issue.stubs(:save)
  end

  def test_destroys_worktree_and_cleans_issue_tracker
    Dir.stubs(:exist?).with(@worktree_path).returns(true)
    Open3.stubs(:capture3).returns(["", "", mock_success_status])

    result = Adw::Actors::DestroyWorktree.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      issue_tracker: @issue_tracker_data
    )

    assert result.success?
    assert_nil result.issue_tracker[:worktree_path]
    assert_nil result.issue_tracker[:backend_port]
    assert_nil result.issue_tracker[:frontend_port]
    assert_nil result.issue_tracker[:postgres_port]
    assert_nil result.issue_tracker[:compose_project]
  end

  def test_skips_when_no_worktree_path
    issue_tracker_no_wt = build_issue_tracker
    issue_tracker_no_wt.delete(:worktree_path)

    result = Adw::Actors::DestroyWorktree.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      issue_tracker: issue_tracker_no_wt
    )

    assert result.success?
  end

  def test_skips_when_worktree_dir_does_not_exist
    Dir.stubs(:exist?).with(@worktree_path).returns(false)

    result = Adw::Actors::DestroyWorktree.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      issue_tracker: @issue_tracker_data
    )

    assert result.success?
  end

  def test_script_failure_is_non_blocking
    Dir.stubs(:exist?).with(@worktree_path).returns(true)
    Open3.stubs(:capture3).returns(["", "some error", mock_failure_status])

    result = Adw::Actors::DestroyWorktree.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      issue_tracker: @issue_tracker_data
    )

    assert result.success?
    assert_nil result.issue_tracker[:worktree_path]
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
