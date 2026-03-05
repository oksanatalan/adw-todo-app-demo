# frozen_string_literal: true

require_relative "../../../test_helper"

class InitializeWorkflowTrackerTest < Minitest::Test
  include TestFactories

  def setup
    @issue_number = 42
    @adw_id = "abc12345"
    @logger = build_logger
  end

  def test_creates_workflow_tracker_with_defaults
    result = Adw::Actors::InitializeWorkflowTracker.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    assert result.success?
    assert_equal @adw_id, result.tracker[:adw_id]
    assert_equal "full_pipeline", result.tracker[:workflow_type]
  end

  def test_uses_custom_workflow_type
    result = Adw::Actors::InitializeWorkflowTracker.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      workflow_type: "plan_build"
    )

    assert result.success?
    assert_equal "plan_build", result.tracker[:workflow_type]
  end
end
