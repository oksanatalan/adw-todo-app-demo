# frozen_string_literal: true

require_relative "../test_helper"

class AdwPatchTest < Minitest::Test
  include TestFactories

  def setup
    @issue_number = "42"
    @adw_id = "test1234"
    @logger = build_logger
    @comment_body = "Fix the button color"
    @main_tracker = build_tracker(branch_name: "feature/test-123", status: "done")

    # Stub external I/O
    Adw::GitHub.stubs(:repo_url).returns("https://github.com/test/repo")
    Adw::GitHub.stubs(:extract_repo_path).returns("test/repo")
    Adw::GitHub.stubs(:fetch_issue).returns(build_issue(number: 42))
    Adw::GitHub.stubs(:create_issue_comment).returns("123")
    Adw::GitHub.stubs(:update_issue_comment)
    Adw::GitHub.stubs(:transition_label)
    Adw::Tracker.stubs(:load).returns(@main_tracker)
    Adw::Tracker.stubs(:update)
    Adw::Tracker.stubs(:update_patch)
    Adw::Tracker.stubs(:save)
    Adw::Tracker.stubs(:save_patch)
    Adw::Tracker.stubs(:set_phase_comment)
    Adw::Tracker.stubs(:add_patch)
    Adw::PipelineHelpers.stubs(:plan_path_for).returns(File.join(Adw.project_root, ".issues", "42", "plan.md"))
    Adw::PipelineHelpers.stubs(:parse_issue_review_results).returns({
      success: true, screenshots: [], review_issues: []
    })
    Adw::PipelineHelpers.stubs(:format_evidence_comment).returns("evidence comment")
    Adw::PipelineHelpers.stubs(:link_screenshot_urls)
    Adw::R2.stubs(:upload_evidence).returns([])
    Adw::Utils.stubs(:make_adw_id).returns("patchid1")
    File.stubs(:exist?).returns(false)

    # git commands
    Open3.stubs(:capture3).with("git", "checkout", anything).returns(["", "", FakeProcessStatus.new(true)])
    Open3.stubs(:capture3).with("git", "pull", "origin", anything).returns(["", "", FakeProcessStatus.new(true)])
    Open3.stubs(:capture3).with("git", "status", "--porcelain").returns(["  M file.rb\n", "", FakeProcessStatus.new(true)])
    Open3.stubs(:capture3).with("git", "push", "origin", anything).returns(["", "", FakeProcessStatus.new(true)])
  end

  def success_response(output: "done")
    build_agent_response(output: output, success: true)
  end

  def failure_response(output: "error")
    build_agent_response(output: output, success: false)
  end

  def passing_test_json
    JSON.generate([{ "test_name" => "test_something", "passed" => true,
                     "execution_command" => "ruby -e 'puts 1'", "test_purpose" => "test", "error" => nil }])
  end

  def ok_review_json
    JSON.generate({
      "overall_severity" => "low",
      "summary" => "Code looks good",
      "checks" => [],
      "action_required" => "none",
      "fix_suggestions" => []
    })
  end

  # When no tracker exists, patch should fail early
  def test_fails_when_no_tracker_found
    Adw::Tracker.stubs(:load).returns(nil)

    result = Adw::Workflows::Patch.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      comment_body: @comment_body
    )

    refute result.success?
    assert_match(/No tracker found/, result.error)
  end

  # When issue cannot be fetched, patch should fail
  def test_fails_when_issue_cannot_be_fetched
    Adw::GitHub.stubs(:fetch_issue).returns(nil)

    result = Adw::Workflows::Patch.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      comment_body: @comment_body
    )

    refute result.success?
    assert_match(/Could not fetch issue/, result.error)
  end

  # When tracker has no branch_name, patch should fail
  def test_fails_when_tracker_has_no_branch_name
    tracker_without_branch = build_tracker(branch_name: nil, status: "done")
    Adw::Tracker.stubs(:load).returns(tracker_without_branch)

    result = Adw::Workflows::Patch.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      comment_body: @comment_body
    )

    refute result.success?
    assert_match(/No branch_name/, result.error)
  end

  # When comment is not a patch, should return success with comment_classification != "patch"
  def test_non_patch_comment_returns_success_with_classification
    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "none")  # classify_comment returns "none"
    )

    result = Adw::Workflows::Patch.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      comment_body: "Just a question about the feature"
    )

    assert result.success?, "Expected success for non-patch comment, got error: #{result.error}"
    assert_equal "none", result.comment_classification
  end

  # When comment classification agent fails, comment_classification is nil and pipeline exits early
  def test_agent_failure_during_comment_classification_returns_success_with_nil_classification
    Adw::Agent.stubs(:execute_template).returns(
      failure_response(output: "agent failed")  # classify_comment fails
    )

    result = Adw::Workflows::Patch.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      comment_body: @comment_body
    )

    assert result.success?
    assert_nil result.comment_classification
  end

  # Happy path: patch comment triggers full patch workflow
  def test_happy_path_patch_workflow
    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "patch"),            # classify_comment
      success_response(output: "patch plan made"),  # build patch plan
      success_response(output: "implemented"),       # implement patch
      success_response(output: passing_test_json),  # run tests
      success_response(output: ok_review_json),     # review code
      success_response(output: "visual ok"),         # visual review (non-blocking)
      success_response(output: "docs ok"),           # docs (non-blocking)
      success_response(output: "committed")          # commit
    )

    result = Adw::Workflows::Patch.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      comment_body: @comment_body
    )

    assert result.success?, "Expected success for patch workflow, got error: #{result.error}"
    assert_equal "patch", result.comment_classification
  end

  # Patch plan failure stops the workflow
  def test_fails_when_patch_plan_fails
    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "patch"),             # classify_comment
      failure_response(output: "patch plan error")   # build patch plan fails
    )

    result = Adw::Workflows::Patch.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      comment_body: @comment_body
    )

    refute result.success?
    assert_match(/Patch plan failed/, result.error)
  end

  # Patch implementation failure stops the workflow
  def test_fails_when_patch_implementation_fails
    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "patch"),              # classify_comment
      success_response(output: "plan created"),        # build patch plan
      failure_response(output: "impl error")           # implement fails
    )

    result = Adw::Workflows::Patch.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      comment_body: @comment_body
    )

    refute result.success?
    assert_match(/Patch implementation failed/, result.error)
  end

  # Tests failing stops the patch workflow
  def test_fails_when_tests_fail_after_patch
    failing_test_json = JSON.generate([{
      "test_name" => "test_something", "passed" => false,
      "execution_command" => "ruby -e 'raise'", "test_purpose" => "test", "error" => "assertion failed"
    }])

    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "patch"),             # classify_comment
      success_response(output: "plan created"),       # build patch plan
      success_response(output: "implemented"),        # implement patch
      # Test runs (MAX_TEST_RETRY_ATTEMPTS times with resolvers in between)
      success_response(output: failing_test_json),   # test attempt 1
      success_response(output: "resolved"),           # resolver
      success_response(output: failing_test_json),   # test attempt 2
      success_response(output: "resolved"),           # resolver
      success_response(output: failing_test_json),   # test attempt 3
      success_response(output: "resolved"),           # resolver
      success_response(output: failing_test_json)    # test attempt 4
    )

    result = Adw::Workflows::Patch.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      comment_body: @comment_body
    )

    refute result.success?
    assert_match(/tests failed/, result.error)
  end

  # setup_logger should be called for patch_adw_id so execution.log is created alongside agent outputs
  def test_creates_execution_log_for_patch_adw_id
    Adw::Utils.expects(:setup_logger)
      .with(@issue_number, "patchid1", "adw_patch")
      .returns(@logger).once

    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "patch"),
      success_response(output: "patch plan made"),
      success_response(output: "implemented"),
      success_response(output: passing_test_json),
      success_response(output: ok_review_json),
      success_response(output: "visual ok"),
      success_response(output: "docs ok"),
      success_response(output: "committed")
    )

    result = Adw::Workflows::Patch.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      comment_body: @comment_body
    )

    assert result.success?, "Expected success, got error: #{result.error}"
  end

  # setup_logger for patch_adw_id should NOT be called when comment is not a patch
  def test_does_not_create_execution_log_when_comment_is_not_patch
    Adw::Utils.expects(:setup_logger).with(@issue_number, "patchid1", "adw_patch").never

    Adw::Agent.stubs(:execute_template).returns(
      success_response(output: "none")
    )

    result = Adw::Workflows::Patch.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      comment_body: "Just a comment"
    )

    assert result.success?
    assert_equal "none", result.comment_classification
  end

  # When git checkout fails, patch should fail
  def test_fails_when_checkout_fails
    Open3.stubs(:capture3).with("git", "checkout", anything).returns(["", "error: not found", FakeProcessStatus.new(false)])

    Adw::Agent.stubs(:execute_template).returns(
      # No calls needed since checkout fails first
    )

    result = Adw::Workflows::Patch.result(
      issue_number: @issue_number,
      adw_id: @adw_id,
      logger: @logger,
      comment_body: @comment_body
    )

    refute result.success?
    assert_match(/checkout|branch/, result.error)
  end
end
