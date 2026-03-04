# frozen_string_literal: true

require_relative "../../../test_helper"

class DestroyWorktreeTest < Minitest::Test
  include TestFactories

  def setup
    @issue_number = 42
    @adw_id = "abc12345"
    @logger = build_logger
    @worktree_path = "/abs/path/trees/feat-42-abc12345-add-login"
    @tracker = build_tracker.merge(
      worktree_path: @worktree_path,
      backend_port: 8042,
      frontend_port: 9042,
      postgres_port: 5442,
      compose_project: "adw-test"
    )

    Adw::Tracker.stubs(:update)
    Adw::Tracker.stubs(:save)
  end

  def test_destroys_worktree_and_cleans_tracker
    Dir.stubs(:exist?).with(@worktree_path).returns(true)
    Open3.stubs(:capture3).returns(["", "", mock_success_status])

    result = Adw::Actors::DestroyWorktree.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      tracker: @tracker
    )

    assert result.success?
    assert_nil result.tracker[:worktree_path]
    assert_nil result.tracker[:backend_port]
    assert_nil result.tracker[:frontend_port]
    assert_nil result.tracker[:postgres_port]
    assert_nil result.tracker[:compose_project]
  end

  def test_skips_when_no_worktree_path
    tracker = build_tracker
    tracker.delete(:worktree_path)

    result = Adw::Actors::DestroyWorktree.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      tracker: tracker
    )

    assert result.success?
  end

  def test_skips_when_worktree_dir_does_not_exist
    Dir.stubs(:exist?).with(@worktree_path).returns(false)

    result = Adw::Actors::DestroyWorktree.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      tracker: @tracker
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
      tracker: @tracker
    )

    assert result.success?
    assert_nil result.tracker[:worktree_path]
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
