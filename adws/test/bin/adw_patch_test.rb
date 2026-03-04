# frozen_string_literal: true

require_relative "../test_helper"
load File.expand_path("../../bin/adw_patch", __dir__)

class AdwPatchTest < Minitest::Test
  include TestFactories

  P = Adw::Pipelines::Patch

  def setup
    @logger = build_logger
    @issue_number = "42"
    @adw_id = "test1234"
    @comment_body = "Fix the button color"
    @issue = build_issue
    @main_tracker = build_tracker(branch_name: "feature/test-123", status: "done")
    @patch_tracker = build_patch_tracker(adw_id: @adw_id)
  end

  # -------------------------------------------------------
  # restore_main_tracker_done
  # -------------------------------------------------------

  def test_restore_main_tracker_done_updates_tracker_and_label
    Adw::Tracker.expects(:update).with(@main_tracker, @issue_number, "done", @logger)
    Adw::GitHub.expects(:transition_label).with(@issue_number, "adw/done", "adw/error")

    P.restore_main_tracker_done(@main_tracker, @issue_number, @logger)
  end

  # -------------------------------------------------------
  # check_patch_error
  # -------------------------------------------------------

  def test_check_patch_error_with_failed_response_updates_patch_and_restores_main
    response = build_agent_response(output: "something failed", success: false)
    Adw::Tracker.expects(:update_patch).with(@patch_tracker, @issue_number, "error", @logger)
    Adw::Tracker.expects(:update).with(@main_tracker, @issue_number, "done", @logger)
    Adw::GitHub.expects(:transition_label).with(@issue_number, "adw/done", "adw/error")

    assert_raises(SystemExit) do
      P.check_patch_error(response, @issue_number, "Error prefix", @patch_tracker, @adw_id, @logger, main_tracker: @main_tracker)
    end
  end

  def test_check_patch_error_with_string_error_updates_patch_and_restores_main
    Adw::Tracker.expects(:update_patch).with(@patch_tracker, @issue_number, "error", @logger)
    Adw::Tracker.expects(:update).with(@main_tracker, @issue_number, "done", @logger)
    Adw::GitHub.expects(:transition_label).with(@issue_number, "adw/done", "adw/error")

    assert_raises(SystemExit) do
      P.check_patch_error("some error string", @issue_number, "Error prefix", @patch_tracker, @adw_id, @logger, main_tracker: @main_tracker)
    end
  end

  def test_check_patch_error_with_nil_is_noop
    result = P.check_patch_error(nil, @issue_number, "Error prefix", @patch_tracker, @adw_id, @logger, main_tracker: @main_tracker)
    assert_nil result
  end

  def test_check_patch_error_with_successful_response_is_noop
    response = build_agent_response(output: "all good", success: true)
    result = P.check_patch_error(response, @issue_number, "Error prefix", @patch_tracker, @adw_id, @logger, main_tracker: @main_tracker)
    assert_nil result
  end

  def test_check_patch_error_without_main_tracker_skips_restore
    response = build_agent_response(output: "failed", success: false)
    Adw::Tracker.expects(:update_patch).with(@patch_tracker, @issue_number, "error", @logger)
    # Should NOT call restore_main_tracker_done, so no Tracker.update or GitHub.transition_label

    assert_raises(SystemExit) do
      P.check_patch_error(response, @issue_number, "Error prefix", @patch_tracker, @adw_id, @logger)
    end
  end

  # -------------------------------------------------------
  # classify_comment
  # -------------------------------------------------------

  def test_classify_comment_returns_patch
    response = build_agent_response(output: "  PATCH  \n", success: true)
    Adw::Agent.expects(:execute_template).returns(response)

    result = P.classify_comment(@comment_body, @issue_number, @adw_id, @logger)
    assert_equal "patch", result
  end

  def test_classify_comment_returns_none
    response = build_agent_response(output: "none", success: true)
    Adw::Agent.expects(:execute_template).returns(response)

    result = P.classify_comment(@comment_body, @issue_number, @adw_id, @logger)
    assert_equal "none", result
  end

  def test_classify_comment_returns_nil_on_failure
    response = build_agent_response(output: "error occurred", success: false)
    Adw::Agent.expects(:execute_template).returns(response)

    result = P.classify_comment(@comment_body, @issue_number, @adw_id, @logger)
    assert_nil result
  end

  # -------------------------------------------------------
  # find_original_plan
  # -------------------------------------------------------

  def test_find_original_plan_when_plan_exists
    File.stubs(:exist?).with(".issues/42/plan.md").returns(true)

    result = P.find_original_plan(@issue_number)
    assert_equal ".issues/42/plan.md", result
  end

  def test_find_original_plan_when_plan_does_not_exist
    File.stubs(:exist?).with(".issues/42/plan.md").returns(false)

    result = P.find_original_plan(@issue_number)
    assert_equal "", result
  end

  # -------------------------------------------------------
  # create_patch_plan
  # -------------------------------------------------------

  def test_create_patch_plan_with_existing_plan_path
    plan_path = ".issues/42/plan.md"
    response = build_agent_response(output: " .issues/42/patch-1-fix.md ", success: true)

    Adw::Agent.expects(:execute_template).with do |req|
      req.args.include?(plan_path) &&
        req.agent_name == "patch_planner" &&
        req.slash_command == "/adw:patch"
    end.returns(response)

    patch_file, error = P.create_patch_plan(@adw_id, @comment_body, plan_path, @issue_number, @logger)
    assert_equal ".issues/42/patch-1-fix.md", patch_file
    assert_nil error
  end

  def test_create_patch_plan_without_plan_path
    response = build_agent_response(output: ".issues/42/patch-1-fix.md", success: true)

    Adw::Agent.expects(:execute_template).with do |req|
      # When plan_path is empty, it should NOT be in args
      !req.args.include?("") &&
        req.args.length == 3 # [adw_id, change_request, issue_number]
    end.returns(response)

    patch_file, error = P.create_patch_plan(@adw_id, @comment_body, "", @issue_number, @logger)
    assert_equal ".issues/42/patch-1-fix.md", patch_file
    assert_nil error
  end

  def test_create_patch_plan_failure
    response = build_agent_response(output: "agent failed", success: false)
    Adw::Agent.expects(:execute_template).returns(response)

    patch_file, error = P.create_patch_plan(@adw_id, @comment_body, "", @issue_number, @logger)
    assert_nil patch_file
    assert_equal "agent failed", error
  end

  # -------------------------------------------------------
  # implement_patch
  # -------------------------------------------------------

  def test_implement_patch_uses_correct_slash_command_and_args
    patch_file = ".issues/42/patch-1-fix.md"
    response = build_agent_response(output: "done", success: true)

    Adw::Agent.expects(:execute_template).with do |req|
      req.slash_command == "/implement" &&
        req.args == [patch_file] &&
        req.agent_name == "patch_implementor"
    end.returns(response)

    result = P.implement_patch(patch_file, @issue_number, @adw_id, @logger)
    assert result.success
  end

  # -------------------------------------------------------
  # log_test_results
  # -------------------------------------------------------

  def test_log_test_results_with_all_passing
    results = [build_test_result(test_name: "test_a", passed: true)]

    Adw::GitHub.expects(:create_issue_comment).with do |num, body|
      num == @issue_number && body.include?("passed")
    end.returns("comment_999")
    Adw::Tracker.expects(:set_phase_comment).with(@patch_tracker, "test", "comment_999")
    Adw::Tracker.expects(:save_patch).with(@issue_number, @adw_id, @patch_tracker)

    P.log_test_results(@issue_number, @adw_id, results, 1, 0, @logger, @patch_tracker)
  end

  def test_log_test_results_with_failures
    results = [
      build_test_result(test_name: "test_a", passed: true),
      build_test_result(test_name: "test_b", passed: false, error: "Expected X got Y")
    ]

    Adw::GitHub.expects(:create_issue_comment).with do |num, body|
      num == @issue_number && body.include?("failed")
    end.returns("comment_999")
    Adw::Tracker.expects(:set_phase_comment)
    Adw::Tracker.expects(:save_patch)

    P.log_test_results(@issue_number, @adw_id, results, 1, 1, @logger, @patch_tracker)
  end

  # -------------------------------------------------------
  # parse_review_results
  # -------------------------------------------------------

  def test_parse_review_results_valid_json
    json = JSON.generate({
      "overall_severity" => "low",
      "summary" => "Looks good",
      "checks" => [{ "name" => "style", "result" => "PASS", "severity" => "low", "details" => "ok" }],
      "action_required" => "none",
      "fix_suggestions" => []
    })

    result = P.parse_review_results(json, @logger)
    assert_equal "low", result[:overall_severity]
    assert_equal "Looks good", result[:summary]
    assert_equal 1, result[:checks].length
    assert_equal "none", result[:action_required]
  end

  def test_parse_review_results_with_markdown_wrapper
    json = "```json\n{\"overall_severity\": \"low\", \"summary\": \"ok\"}\n```"

    result = P.parse_review_results(json, @logger)
    assert_equal "low", result[:overall_severity]
  end

  def test_parse_review_results_invalid_json
    result = P.parse_review_results("not json at all", @logger)
    assert_equal "warning", result[:overall_severity]
    assert_equal "none", result[:action_required]
  end

  # -------------------------------------------------------
  # format_review_comment
  # -------------------------------------------------------

  def test_format_review_comment_with_checks
    review_result = {
      overall_severity: "low",
      summary: "All good",
      checks: [{ "name" => "style", "result" => "PASS", "severity" => "low", "details" => "clean" }],
      fix_suggestions: []
    }

    comment = P.format_review_comment(review_result)
    assert_includes comment, "Resultados de Revision de Codigo"
    assert_includes comment, "low"
    assert_includes comment, "style"
  end

  def test_format_review_comment_with_fix_suggestions
    review_result = {
      overall_severity: "medium",
      summary: "Some issues",
      checks: [],
      fix_suggestions: ["Fix indentation", "Remove unused import"]
    }

    comment = P.format_review_comment(review_result)
    assert_includes comment, "Sugerencias de correccion"
    assert_includes comment, "Fix indentation"
  end

  def test_format_review_comment_without_checks_or_suggestions
    review_result = {
      overall_severity: "low",
      summary: "All good",
      checks: [],
      fix_suggestions: []
    }

    comment = P.format_review_comment(review_result)
    assert_includes comment, "low"
    refute_includes comment, "Criterio"
    refute_includes comment, "Sugerencias"
  end

  # -------------------------------------------------------
  # handle_review_fixes
  # -------------------------------------------------------

  def test_handle_review_fixes_successful_fix
    initial_review = {
      overall_severity: "medium",
      action_required: "fix_and_rerun",
      fix_suggestions: ["Fix X"],
      checks: [{ "name" => "style", "result" => "FAIL", "severity" => "medium", "details" => "bad" }]
    }

    fix_response = build_agent_response(output: "fixed", success: true)
    fixed_json = JSON.generate({
      "overall_severity" => "low",
      "summary" => "Fixed",
      "checks" => [{ "name" => "style", "result" => "PASS", "severity" => "low", "details" => "ok" }],
      "action_required" => "none",
      "fix_suggestions" => []
    })
    recheck_response = build_agent_response(output: fixed_json, success: true)

    Adw::Agent.expects(:execute_template).twice.returns(fix_response, recheck_response)
    Adw::GitHub.expects(:create_issue_comment).returns("c1")

    plan_path = ".issues/42/plan.md"
    result = P.handle_review_fixes(initial_review, @adw_id, @issue_number, @issue, plan_path, @logger)
    assert_equal "none", result[:action_required]
  end

  def test_handle_review_fixes_fix_agent_fails
    initial_review = {
      overall_severity: "medium",
      action_required: "fix_and_rerun",
      fix_suggestions: ["Fix X"],
      checks: [{ "name" => "style", "result" => "FAIL", "severity" => "medium", "details" => "bad" }]
    }

    fix_response = build_agent_response(output: "failed", success: false)
    Adw::Agent.expects(:execute_template).returns(fix_response)

    plan_path = ".issues/42/plan.md"
    result = P.handle_review_fixes(initial_review, @adw_id, @issue_number, @issue, plan_path, @logger)
    # Should return the original review_result unchanged
    assert_equal "fix_and_rerun", result[:action_required]
  end

  def test_handle_review_fixes_recheck_fails
    initial_review = {
      overall_severity: "medium",
      action_required: "fix_and_rerun",
      fix_suggestions: ["Fix X"],
      checks: []
    }

    fix_response = build_agent_response(output: "fixed", success: true)
    recheck_response = build_agent_response(output: "error", success: false)

    Adw::Agent.expects(:execute_template).twice.returns(fix_response, recheck_response)

    plan_path = ".issues/42/plan.md"
    result = P.handle_review_fixes(initial_review, @adw_id, @issue_number, @issue, plan_path, @logger)
    assert_equal "fix_and_rerun", result[:action_required]
  end

  # -------------------------------------------------------
  # run_review
  # -------------------------------------------------------

  def test_run_review_success_no_fixes_needed
    review_json = JSON.generate({
      "overall_severity" => "low",
      "summary" => "Clean code",
      "checks" => [],
      "action_required" => "none",
      "fix_suggestions" => []
    })

    response = build_agent_response(output: review_json, success: true)
    Adw::Agent.expects(:execute_template).returns(response)
    Adw::GitHub.expects(:create_issue_comment).returns("review_comment_1")
    Adw::Tracker.expects(:set_phase_comment).with(@patch_tracker, "review_tech", "review_comment_1")
    Adw::Tracker.expects(:save_patch).with(@issue_number, @adw_id, @patch_tracker)

    result = P.run_review(@adw_id, @issue_number, @issue, @patch_tracker, @logger)
    assert_equal "low", result[:overall_severity]
    assert_equal "none", result[:action_required]
  end

  def test_run_review_agent_failure
    response = build_agent_response(output: "agent crashed", success: false)
    Adw::Agent.expects(:execute_template).returns(response)

    result = P.run_review(@adw_id, @issue_number, @issue, @patch_tracker, @logger)
    assert_equal "error", result[:overall_severity]
    assert_equal "none", result[:action_required]
  end

  # -------------------------------------------------------
  # run_issue_review
  # -------------------------------------------------------

  def test_run_issue_review_agent_failure
    response = build_agent_response(output: "crashed", success: false)
    Adw::Agent.expects(:execute_template).returns(response)
    Adw::GitHub.expects(:create_issue_comment).returns("c1")

    result = P.run_issue_review(@adw_id, @issue_number, @issue, @patch_tracker, @logger)
    assert_nil result
  end

  def test_run_issue_review_no_screenshots
    review_json = JSON.generate({
      "success" => true,
      "summary" => "Looks fine",
      "plan_adherence" => nil,
      "review_issues" => [],
      "screenshots" => [],
      "errors" => []
    })

    response = build_agent_response(output: review_json, success: true)
    Adw::Agent.expects(:execute_template).returns(response)

    result = P.run_issue_review(@adw_id, @issue_number, @issue, @patch_tracker, @logger)
    assert_equal true, result[:success]
    assert_empty result[:screenshots]
  end

  def test_run_issue_review_success_not_true_returns_early
    review_json = JSON.generate({
      "success" => false,
      "summary" => "Failed",
      "screenshots" => [],
      "review_issues" => [],
      "errors" => ["Some error"]
    })

    response = build_agent_response(output: review_json, success: true)
    Adw::Agent.expects(:execute_template).returns(response)

    result = P.run_issue_review(@adw_id, @issue_number, @issue, @patch_tracker, @logger)
    assert_equal false, result[:success]
  end

  # -------------------------------------------------------
  # run_documentation
  # -------------------------------------------------------

  def test_run_documentation_agent_failure
    response = build_agent_response(output: "failed", success: false)
    Adw::Agent.expects(:execute_template).returns(response)

    result = P.run_documentation(@adw_id, @issue_number, @patch_tracker, @logger)
    assert_nil result
  end

  def test_run_documentation_success
    doc_content = "## Overview\nThis is an overview.\n## Que se Construyo\nNew feature.\n## End\n"
    response = build_agent_response(output: " app_docs/doc.md ", success: true)
    Adw::Agent.expects(:execute_template).returns(response)
    File.stubs(:read).with("app_docs/doc.md").returns(doc_content)
    Adw::GitHub.expects(:create_issue_comment).returns("doc_c1")
    Adw::Tracker.expects(:set_phase_comment).with(@patch_tracker, "document", "doc_c1")
    Adw::Tracker.expects(:save_patch).with(@issue_number, @adw_id, @patch_tracker)

    P.run_documentation(@adw_id, @issue_number, @patch_tracker, @logger)
  end

  # -------------------------------------------------------
  # post_documentation_summary
  # -------------------------------------------------------

  def test_post_documentation_summary_with_overview_and_changes
    doc_content = "## Overview\nOverview text here.\n## Que se Construyo\nBuilt something.\n## End\n"
    File.stubs(:read).with("app_docs/doc.md").returns(doc_content)
    Adw::GitHub.expects(:create_issue_comment).with do |num, body|
      num == @issue_number &&
        body.include?("Overview text here") &&
        body.include?("Built something")
    end.returns("dc1")
    Adw::Tracker.expects(:set_phase_comment).with(@patch_tracker, "document", "dc1")
    Adw::Tracker.expects(:save_patch)

    P.post_documentation_summary(@issue_number, @adw_id, "app_docs/doc.md", @patch_tracker, @logger)
  end

  def test_post_documentation_summary_handles_file_not_found
    File.stubs(:read).raises(Errno::ENOENT.new("no such file"))

    # Should not raise, just log warning
    P.post_documentation_summary(@issue_number, @adw_id, "missing.md", @patch_tracker, @logger)
  end

  # -------------------------------------------------------
  # commit_and_push
  # -------------------------------------------------------

  def test_commit_and_push_no_changes
    Open3.stubs(:capture3).with("git", "status", "--porcelain")
         .returns(["", "", FakeProcessStatus.new(true)])

    P.commit_and_push(@issue_number, @adw_id, @patch_tracker, @logger, main_tracker: @main_tracker)
    # No commit or push should happen
  end

  def test_commit_and_push_with_changes_success
    Open3.stubs(:capture3).with("git", "status", "--porcelain")
         .returns(["M file.rb\n", "", FakeProcessStatus.new(true)])

    commit_response = build_agent_response(output: "committed", success: true)
    Adw::Agent.expects(:execute_template).returns(commit_response)

    Open3.stubs(:capture3).with("git", "push")
         .returns(["", "", FakeProcessStatus.new(true)])

    P.commit_and_push(@issue_number, @adw_id, @patch_tracker, @logger, main_tracker: @main_tracker)
  end

  def test_commit_and_push_commit_fails
    Open3.stubs(:capture3).with("git", "status", "--porcelain")
         .returns(["M file.rb\n", "", FakeProcessStatus.new(true)])

    commit_response = build_agent_response(output: "commit failed", success: false)
    Adw::Agent.expects(:execute_template).returns(commit_response)

    Adw::Tracker.expects(:update_patch).with(@patch_tracker, @issue_number, "error", @logger)
    Adw::Tracker.expects(:update).with(@main_tracker, @issue_number, "done", @logger)
    Adw::GitHub.expects(:transition_label)

    assert_raises(SystemExit) do
      P.commit_and_push(@issue_number, @adw_id, @patch_tracker, @logger, main_tracker: @main_tracker)
    end
  end

  def test_commit_and_push_push_fails_logs_warning
    Open3.stubs(:capture3).with("git", "status", "--porcelain")
         .returns(["M file.rb\n", "", FakeProcessStatus.new(true)])

    commit_response = build_agent_response(output: "committed", success: true)
    Adw::Agent.expects(:execute_template).returns(commit_response)

    Open3.stubs(:capture3).with("git", "push")
         .returns(["", "push rejected", FakeProcessStatus.new(false)])

    # Should not raise, just log warning
    P.commit_and_push(@issue_number, @adw_id, @patch_tracker, @logger, main_tracker: @main_tracker)
  end

  # -------------------------------------------------------
  # checkout_branch
  # -------------------------------------------------------

  def test_checkout_branch_success
    Open3.stubs(:capture3).with("git", "checkout", "feature/test-123")
         .returns(["", "", FakeProcessStatus.new(true)])
    Open3.stubs(:capture3).with("git", "pull", "--rebase")
         .returns(["", "", FakeProcessStatus.new(true)])

    result = P.checkout_branch("feature/test-123", @logger)
    assert result
  end

  def test_checkout_branch_checkout_fails
    Open3.stubs(:capture3).with("git", "checkout", "feature/test-123")
         .returns(["", "error: not found", FakeProcessStatus.new(false)])

    result = P.checkout_branch("feature/test-123", @logger)
    refute result
  end

  def test_checkout_branch_pull_fails_still_returns_true
    Open3.stubs(:capture3).with("git", "checkout", "feature/test-123")
         .returns(["", "", FakeProcessStatus.new(true)])
    Open3.stubs(:capture3).with("git", "pull", "--rebase")
         .returns(["", "conflict", FakeProcessStatus.new(false)])

    result = P.checkout_branch("feature/test-123", @logger)
    assert result
  end

  # -------------------------------------------------------
  # main flow tests (dual tracker)
  # -------------------------------------------------------

  def test_main_happy_path
    # Stub parse_args
    P.stubs(:parse_args).returns([@issue_number, @comment_body, @adw_id])
    Adw::Utils.stubs(:setup_logger).returns(@logger)

    # Load tracker
    Adw::Tracker.stubs(:load).with(@issue_number).returns(@main_tracker)

    # Checkout branch
    Open3.stubs(:capture3).with("git", "checkout", "feature/test-123")
         .returns(["", "", FakeProcessStatus.new(true)])
    Open3.stubs(:capture3).with("git", "pull", "--rebase")
         .returns(["", "", FakeProcessStatus.new(true)])

    # Classify as "patch"
    classify_response = build_agent_response(output: "patch", success: true)

    # Fetch issue
    Adw::GitHub.stubs(:extract_repo_path).returns("owner/repo")
    Adw::GitHub.stubs(:repo_url).returns("https://github.com/owner/repo")
    Adw::GitHub.stubs(:fetch_issue).returns(@issue)

    # Track all tracker status updates
    main_statuses = []
    patch_statuses = []
    Adw::Tracker.stubs(:update).with do |tracker, _num, status, _log|
      main_statuses << status
      true
    end
    Adw::Tracker.stubs(:update_patch).with do |tracker, _num, status, _log|
      patch_statuses << status
      true
    end

    # Create patch plan
    plan_response = build_agent_response(output: ".issues/42/patch-1.md", success: true)

    # Implement
    implement_response = build_agent_response(output: "implemented", success: true)

    # Tests pass
    test_results = [build_test_result(test_name: "test_a", passed: true)]

    # Review
    review_json = JSON.generate({
      "overall_severity" => "low",
      "summary" => "ok",
      "checks" => [],
      "action_required" => "none",
      "fix_suggestions" => []
    })
    review_response = build_agent_response(output: review_json, success: true)

    # Issue review - no screenshots
    issue_review_json = JSON.generate({
      "success" => true,
      "summary" => "Looks fine",
      "plan_adherence" => nil,
      "review_issues" => [],
      "screenshots" => [],
      "errors" => []
    })
    issue_review_response = build_agent_response(output: issue_review_json, success: true)

    # Documentation
    doc_response = build_agent_response(output: "app_docs/doc.md", success: true)

    # Commit and push - no changes
    Open3.stubs(:capture3).with("git", "status", "--porcelain")
         .returns(["", "", FakeProcessStatus.new(true)])

    Adw::Agent.stubs(:execute_template).returns(
      classify_response,   # classify_comment
      plan_response,       # create_patch_plan
      implement_response,  # implement_patch
      # run_tests_with_resolution will call this too
      review_response,     # run_review
      issue_review_response, # run_issue_review
      doc_response         # run_documentation
    )

    # run_tests_with_resolution needs special handling
    P.stubs(:run_tests_with_resolution).returns([test_results, 1, 0])

    # Stubs for GitHub comment creation
    Adw::GitHub.stubs(:create_issue_comment).returns("c1")

    # Stubs for file operations
    File.stubs(:exist?).with(".issues/42/plan.md").returns(false)
    File.stubs(:read).with("app_docs/doc.md").returns("## Overview\nSome overview.\n## End\n")

    # Stubs for tracker persistence
    Adw::Tracker.stubs(:set_phase_comment)
    Adw::Tracker.stubs(:save_patch)
    Adw::Tracker.stubs(:save)
    Adw::Tracker.stubs(:add_patch)

    # post_plan_comment
    P.stubs(:post_plan_comment).returns("plan_c1")

    P.main

    # Verify main tracker went: patching -> done
    assert_includes main_statuses, "patching"
    assert_includes main_statuses, "done"

    # Verify patch tracker went through expected states
    assert_includes patch_statuses, "patching"
    assert_includes patch_statuses, "implementing"
    assert_includes patch_statuses, "testing"
    assert_includes patch_statuses, "reviewing"
    assert_includes patch_statuses, "reviewing_issue"
    assert_includes patch_statuses, "documenting"
    assert_includes patch_statuses, "committing"
    assert_includes patch_statuses, "done"
  end

  def test_main_classify_none_exits_0
    P.stubs(:parse_args).returns([@issue_number, @comment_body, @adw_id])
    Adw::Utils.stubs(:setup_logger).returns(@logger)
    Adw::Tracker.stubs(:load).with(@issue_number).returns(@main_tracker)

    Open3.stubs(:capture3).with("git", "checkout", "feature/test-123")
         .returns(["", "", FakeProcessStatus.new(true)])
    Open3.stubs(:capture3).with("git", "pull", "--rebase")
         .returns(["", "", FakeProcessStatus.new(true)])

    classify_response = build_agent_response(output: "none", success: true)
    Adw::Agent.stubs(:execute_template).returns(classify_response)
    Adw::GitHub.stubs(:create_issue_comment).returns("c1")

    exit_code = nil
    begin
      P.main
    rescue SystemExit => e
      exit_code = e.status
    end

    assert_equal 0, exit_code
  end

  def test_main_no_tracker_exits_1
    P.stubs(:parse_args).returns([@issue_number, @comment_body, @adw_id])
    Adw::Utils.stubs(:setup_logger).returns(@logger)
    Adw::Tracker.stubs(:load).with(@issue_number).returns(nil)

    exit_code = nil
    begin
      P.main
    rescue SystemExit => e
      exit_code = e.status
    end

    assert_equal 1, exit_code
  end

  def test_main_no_branch_name_exits_1
    tracker_no_branch = build_tracker(branch_name: nil, status: "done")
    P.stubs(:parse_args).returns([@issue_number, @comment_body, @adw_id])
    Adw::Utils.stubs(:setup_logger).returns(@logger)
    Adw::Tracker.stubs(:load).with(@issue_number).returns(tracker_no_branch)

    exit_code = nil
    begin
      P.main
    rescue SystemExit => e
      exit_code = e.status
    end

    assert_equal 1, exit_code
  end

  def test_main_checkout_branch_fails_exits_1
    P.stubs(:parse_args).returns([@issue_number, @comment_body, @adw_id])
    Adw::Utils.stubs(:setup_logger).returns(@logger)
    Adw::Tracker.stubs(:load).with(@issue_number).returns(@main_tracker)

    Open3.stubs(:capture3).with("git", "checkout", "feature/test-123")
         .returns(["", "error", FakeProcessStatus.new(false)])

    exit_code = nil
    begin
      P.main
    rescue SystemExit => e
      exit_code = e.status
    end

    assert_equal 1, exit_code
  end

  def test_main_patch_plan_fails_error_and_restore
    P.stubs(:parse_args).returns([@issue_number, @comment_body, @adw_id])
    Adw::Utils.stubs(:setup_logger).returns(@logger)
    Adw::Tracker.stubs(:load).with(@issue_number).returns(@main_tracker)

    Open3.stubs(:capture3).with("git", "checkout", "feature/test-123")
         .returns(["", "", FakeProcessStatus.new(true)])
    Open3.stubs(:capture3).with("git", "pull", "--rebase")
         .returns(["", "", FakeProcessStatus.new(true)])

    # Classify as "patch"
    classify_response = build_agent_response(output: "patch", success: true)

    Adw::GitHub.stubs(:extract_repo_path).returns("owner/repo")
    Adw::GitHub.stubs(:repo_url).returns("https://github.com/owner/repo")
    Adw::GitHub.stubs(:fetch_issue).returns(@issue)

    # Patch plan fails
    plan_response = build_agent_response(output: "plan failed", success: false)

    Adw::Agent.stubs(:execute_template).returns(classify_response, plan_response)
    File.stubs(:exist?).with(".issues/42/plan.md").returns(false)

    Adw::Tracker.stubs(:update)
    Adw::Tracker.stubs(:update_patch)
    Adw::GitHub.stubs(:transition_label)

    exit_code = nil
    begin
      P.main
    rescue SystemExit => e
      exit_code = e.status
    end

    assert_equal 1, exit_code
  end

  def test_main_implementation_fails_error_and_restore
    P.stubs(:parse_args).returns([@issue_number, @comment_body, @adw_id])
    Adw::Utils.stubs(:setup_logger).returns(@logger)
    Adw::Tracker.stubs(:load).with(@issue_number).returns(@main_tracker)

    Open3.stubs(:capture3).with("git", "checkout", "feature/test-123")
         .returns(["", "", FakeProcessStatus.new(true)])
    Open3.stubs(:capture3).with("git", "pull", "--rebase")
         .returns(["", "", FakeProcessStatus.new(true)])

    classify_response = build_agent_response(output: "patch", success: true)
    plan_response = build_agent_response(output: ".issues/42/patch-1.md", success: true)
    implement_response = build_agent_response(output: "implementation crashed", success: false)

    Adw::GitHub.stubs(:extract_repo_path).returns("owner/repo")
    Adw::GitHub.stubs(:repo_url).returns("https://github.com/owner/repo")
    Adw::GitHub.stubs(:fetch_issue).returns(@issue)

    Adw::Agent.stubs(:execute_template).returns(classify_response, plan_response, implement_response)
    File.stubs(:exist?).with(".issues/42/plan.md").returns(false)

    Adw::Tracker.stubs(:update)
    Adw::Tracker.stubs(:update_patch)
    Adw::Tracker.stubs(:set_phase_comment)
    Adw::Tracker.stubs(:save_patch)
    Adw::Tracker.stubs(:save)
    Adw::Tracker.stubs(:add_patch)
    Adw::GitHub.stubs(:create_issue_comment).returns("c1")
    Adw::GitHub.stubs(:transition_label)

    P.stubs(:post_plan_comment).returns("plan_c1")

    exit_code = nil
    begin
      P.main
    rescue SystemExit => e
      exit_code = e.status
    end

    assert_equal 1, exit_code
  end

  def test_main_tests_fail_error_and_restore
    P.stubs(:parse_args).returns([@issue_number, @comment_body, @adw_id])
    Adw::Utils.stubs(:setup_logger).returns(@logger)
    Adw::Tracker.stubs(:load).with(@issue_number).returns(@main_tracker)

    Open3.stubs(:capture3).with("git", "checkout", "feature/test-123")
         .returns(["", "", FakeProcessStatus.new(true)])
    Open3.stubs(:capture3).with("git", "pull", "--rebase")
         .returns(["", "", FakeProcessStatus.new(true)])

    classify_response = build_agent_response(output: "patch", success: true)
    plan_response = build_agent_response(output: ".issues/42/patch-1.md", success: true)
    implement_response = build_agent_response(output: "done", success: true)

    Adw::GitHub.stubs(:extract_repo_path).returns("owner/repo")
    Adw::GitHub.stubs(:repo_url).returns("https://github.com/owner/repo")
    Adw::GitHub.stubs(:fetch_issue).returns(@issue)

    Adw::Agent.stubs(:execute_template).returns(classify_response, plan_response, implement_response)
    File.stubs(:exist?).with(".issues/42/plan.md").returns(false)

    # Tests fail
    failed_results = [build_test_result(test_name: "test_a", passed: false, error: "bad")]
    P.stubs(:run_tests_with_resolution).returns([failed_results, 0, 1])

    Adw::Tracker.stubs(:update)
    Adw::Tracker.stubs(:update_patch)
    Adw::Tracker.stubs(:set_phase_comment)
    Adw::Tracker.stubs(:save_patch)
    Adw::Tracker.stubs(:save)
    Adw::Tracker.stubs(:add_patch)
    Adw::GitHub.stubs(:create_issue_comment).returns("c1")
    Adw::GitHub.stubs(:transition_label)

    P.stubs(:post_plan_comment).returns("plan_c1")

    exit_code = nil
    begin
      P.main
    rescue SystemExit => e
      exit_code = e.status
    end

    assert_equal 1, exit_code
  end

  def test_main_review_critical_error_and_restore
    P.stubs(:parse_args).returns([@issue_number, @comment_body, @adw_id])
    Adw::Utils.stubs(:setup_logger).returns(@logger)
    Adw::Tracker.stubs(:load).with(@issue_number).returns(@main_tracker)

    Open3.stubs(:capture3).with("git", "checkout", "feature/test-123")
         .returns(["", "", FakeProcessStatus.new(true)])
    Open3.stubs(:capture3).with("git", "pull", "--rebase")
         .returns(["", "", FakeProcessStatus.new(true)])

    classify_response = build_agent_response(output: "patch", success: true)
    plan_response = build_agent_response(output: ".issues/42/patch-1.md", success: true)
    implement_response = build_agent_response(output: "done", success: true)

    Adw::GitHub.stubs(:extract_repo_path).returns("owner/repo")
    Adw::GitHub.stubs(:repo_url).returns("https://github.com/owner/repo")
    Adw::GitHub.stubs(:fetch_issue).returns(@issue)

    # Review returns critical with fix_and_rerun (after fixes still critical)
    review_json = JSON.generate({
      "overall_severity" => "critical",
      "summary" => "Security issue",
      "checks" => [],
      "action_required" => "fix_and_rerun",
      "fix_suggestions" => ["Fix security"]
    })
    review_response = build_agent_response(output: review_json, success: true)

    # The fix attempt still returns critical
    fix_response = build_agent_response(output: "tried", success: true)
    recheck_json = JSON.generate({
      "overall_severity" => "critical",
      "summary" => "Still bad",
      "checks" => [],
      "action_required" => "fix_and_rerun",
      "fix_suggestions" => ["Try again"]
    })
    recheck_response = build_agent_response(output: recheck_json, success: true)

    Adw::Agent.stubs(:execute_template).returns(
      classify_response, plan_response, implement_response,
      review_response,
      fix_response, recheck_response,
      fix_response, recheck_response
    )
    File.stubs(:exist?).with(".issues/42/plan.md").returns(false)

    test_results = [build_test_result(test_name: "test_a", passed: true)]
    P.stubs(:run_tests_with_resolution).returns([test_results, 1, 0])

    Adw::Tracker.stubs(:update)
    Adw::Tracker.stubs(:update_patch)
    Adw::Tracker.stubs(:set_phase_comment)
    Adw::Tracker.stubs(:save_patch)
    Adw::Tracker.stubs(:save)
    Adw::Tracker.stubs(:add_patch)
    Adw::GitHub.stubs(:create_issue_comment).returns("c1")
    Adw::GitHub.stubs(:transition_label)

    P.stubs(:post_plan_comment).returns("plan_c1")

    exit_code = nil
    begin
      P.main
    rescue SystemExit => e
      exit_code = e.status
    end

    assert_equal 1, exit_code
  end
end
