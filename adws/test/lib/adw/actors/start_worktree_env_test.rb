# frozen_string_literal: true

require_relative "../../../test_helper"

class StartWorktreeEnvTest < Minitest::Test
  include TestFactories

  def setup
    @issue_number = 42
    @adw_id = "abc12345"
    @logger = build_logger
    @worktree_path = "/abs/path/trees/feat-42-abc12345-add-login"
    @tracker = build_tracker
  end

  def test_updates_tracker_to_setting_up
    Adw::Tracker.expects(:update).with(@tracker, @issue_number, "setting_up", @logger)
    Adw::Tracker.stubs(:save)
    Open3.stubs(:capture3).returns(["", "", mock_success_status])

    result = Adw::Actors::StartWorktreeEnv.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      worktree_path: @worktree_path,
      tracker: @tracker
    )

    assert result.success?
  end

  def test_service_failure_is_non_blocking
    Adw::Tracker.stubs(:update)
    Adw::Tracker.stubs(:save)
    Open3.stubs(:capture3).returns(["", "docker error", mock_failure_status])

    result = Adw::Actors::StartWorktreeEnv.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      worktree_path: @worktree_path,
      tracker: @tracker
    )

    assert result.success?
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
