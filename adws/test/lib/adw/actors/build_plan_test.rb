# frozen_string_literal: true

require_relative "../../../test_helper"

class BuildPlanTest < Minitest::Test
  include TestFactories

  def setup
    @issue_number = 42
    @adw_id = "abc12345"
    @logger = build_logger
    @issue = build_issue(number: @issue_number)
    @tracker = build_tracker
    @plan_path = File.join(Adw.project_root, ".issues", "42", "plan.md")

    Adw::Tracker.stubs(:update)
    Adw::PipelineHelpers.stubs(:plan_path_for).with(@issue_number).returns(@plan_path)
  end

  def test_returns_plan_path_and_transitions_to_planning_on_success
    Adw::Tracker.expects(:update).with(@tracker, @issue_number, "planning", @logger)
    Adw::Agent.stubs(:execute_template).returns(build_agent_response(output: "plan created", success: true))

    result = Adw::Actors::BuildPlan.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      issue: @issue,
      issue_command: "/feature",
      tracker: @tracker
    )

    assert result.success?
    assert_equal @plan_path, result.plan_path
  end

  def test_fails_and_transitions_to_error_when_agent_fails
    Adw::Tracker.stubs(:update)
    Adw::Tracker.expects(:update).with(@tracker, @issue_number, "planning", @logger)
    Adw::Tracker.expects(:update).with(@tracker, @issue_number, "error", @logger)
    Adw::Agent.stubs(:execute_template).returns(build_agent_response(output: "agent error", success: false))

    result = Adw::Actors::BuildPlan.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      issue: @issue,
      issue_command: "/feature",
      tracker: @tracker
    )

    refute result.success?
    assert_match(/Plan build failed/, result.error)
  end

  def test_uses_opus_model
    captured_request = nil
    Adw::Agent.stubs(:execute_template).with { |req| captured_request = req; true }
              .returns(build_agent_response(output: "ok", success: true))

    Adw::Actors::BuildPlan.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      issue: @issue,
      issue_command: "/feature",
      tracker: @tracker
    )

    assert_equal "opus", captured_request.model
  end

end
