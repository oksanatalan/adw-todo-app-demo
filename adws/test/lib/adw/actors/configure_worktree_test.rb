# frozen_string_literal: true

require_relative "../../../test_helper"

class ConfigureWorktreeTest < Minitest::Test
  include TestFactories

  def setup
    @issue_number = 42
    @adw_id = "abc12345"
    @logger = build_logger
    @branch_name = "feat-42-abc12345-add-login"
    @worktree_path = "/abs/path/trees/#{@branch_name}"
    @tracker = build_tracker

    Adw::Tracker.stubs(:update)
    Adw::Tracker.stubs(:save)
  end

  def test_parses_port_json_and_updates_tracker
    json = '{"postgres_port":5742,"backend_port":8342,"frontend_port":9342,"compose_project":"adw-feat-42"}'
    Open3.stubs(:capture3).returns([json, "", mock_success_status])

    result = Adw::Actors::ConfigureWorktree.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      branch_name: @branch_name,
      worktree_path: @worktree_path,
      tracker: @tracker
    )

    assert result.success?
    assert_equal 5742, result.tracker[:postgres_port]
    assert_equal 8342, result.tracker[:backend_port]
    assert_equal 9342, result.tracker[:frontend_port]
    assert_equal "adw-feat-42", result.tracker[:compose_project]
  end

  def test_fails_on_script_error
    Open3.stubs(:capture3).returns(["", "openssl not found", mock_failure_status])

    result = Adw::Actors::ConfigureWorktree.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      branch_name: @branch_name,
      worktree_path: @worktree_path,
      tracker: @tracker
    )

    refute result.success?
    assert_match(/Worktree configuration failed/, result.error)
  end

  def test_deterministic_via_script
    json = '{"postgres_port":5742,"backend_port":8342,"frontend_port":9342,"compose_project":"adw-feat-42"}'
    Open3.stubs(:capture3).returns([json, "", mock_success_status])

    result1 = Adw::Actors::ConfigureWorktree.result(
      issue_number: @issue_number, adw_id: @adw_id, logger: @logger,
      branch_name: @branch_name, worktree_path: @worktree_path, tracker: build_tracker
    )

    result2 = Adw::Actors::ConfigureWorktree.result(
      issue_number: @issue_number, adw_id: @adw_id, logger: @logger,
      branch_name: @branch_name, worktree_path: @worktree_path, tracker: build_tracker
    )

    assert_equal result1.tracker[:postgres_port], result2.tracker[:postgres_port]
    assert_equal result1.tracker[:backend_port], result2.tracker[:backend_port]
    assert_equal result1.tracker[:frontend_port], result2.tracker[:frontend_port]
    assert_equal result1.tracker[:compose_project], result2.tracker[:compose_project]
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
