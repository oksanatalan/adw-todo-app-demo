# frozen_string_literal: true

require_relative "../../../test_helper"

class InitializeIssueTrackerTest < Minitest::Test
  include TestFactories

  def setup
    @issue_number = 42
    @adw_id = "abc12345"
    @logger = build_logger

    Adw::Tracker::Issue.stubs(:sync)
  end

  def test_loads_existing_issue_tracker
    existing_issue = { classification: "/feature", branch_name: "feature/test", workflows: [] }
    Adw::Tracker::Issue.stubs(:load).with(@issue_number).returns(existing_issue)

    result = Adw::Actors::InitializeIssueTracker.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    assert result.success?
    assert_equal "/feature", result.issue_tracker[:classification]
    assert_equal "feature/test", result.issue_tracker[:branch_name]
    assert_equal [{ adw_id: @adw_id, type: "full_pipeline" }], result.issue_tracker[:workflows]
  end

  def test_creates_empty_issue_tracker_when_load_returns_nil
    Adw::Tracker::Issue.stubs(:load).with(@issue_number).returns(nil)

    result = Adw::Actors::InitializeIssueTracker.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger
    )

    assert result.success?
    assert_equal [{ adw_id: @adw_id, type: "full_pipeline" }], result.issue_tracker[:workflows]
  end

  def test_sets_branch_name_on_issue_tracker_when_provided
    Adw::Tracker::Issue.stubs(:load).with(@issue_number).returns({})

    result = Adw::Actors::InitializeIssueTracker.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      branch_name: "feature-42-abc12345-test"
    )

    assert result.success?
    assert_equal "feature-42-abc12345-test", result.issue_tracker[:branch_name]
  end
end
