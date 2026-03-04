# frozen_string_literal: true

require_relative "../../../test_helper"

class InstallWorktreeDepsTest < Minitest::Test
  include TestFactories

  def setup
    @issue_number = 42
    @adw_id = "abc12345"
    @logger = build_logger
    @worktree_path = "/abs/path/trees/feat-42-abc12345-add-login"
    @tracker = build_tracker

    Adw::Tracker.stubs(:update)
    Adw::Tracker.stubs(:save)
  end

  def test_updates_tracker_to_installing_deps
    Adw::Tracker.expects(:update).with(@tracker, @issue_number, "installing_deps", @logger)
    Open3.stubs(:capture3).returns(["", "", mock_success_status])

    result = run_actor

    assert result.success?
  end

  def test_succeeds_when_script_exits_zero
    Open3.stubs(:capture3).returns(["", "", mock_success_status])

    result = run_actor

    assert result.success?
  end

  def test_fails_when_script_exits_nonzero
    Open3.stubs(:capture3).returns(["", "bundle install failed: Gemfile not found", mock_failure_status])

    result = run_actor

    refute result.success?
    assert_match(/Dependency installation failed/, result.error)
  end

  private

  def run_actor
    Adw::Actors::InstallWorktreeDeps.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      worktree_path: @worktree_path,
      tracker: @tracker
    )
  end

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
