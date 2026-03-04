# frozen_string_literal: true

require_relative "../test_helper"
load File.expand_path("../../bin/adw_full_pipeline", __dir__)

class AdwFullPipelineTest < Minitest::Test
  include TestHelpers

  Pipeline = Adw::Pipelines::FullPipeline

  # ─── parse_review_results ───────────────────────────────────────────

  def test_parse_review_results_valid_json
    json = JSON.generate({
      "overall_severity" => "low",
      "summary" => "Code looks good",
      "checks" => [
        { "name" => "security", "result" => "PASS", "severity" => "low", "details" => "No issues" }
      ],
      "action_required" => "none",
      "fix_suggestions" => []
    })

    result = Pipeline.parse_review_results(json, mock_logger)

    assert_equal "low", result[:overall_severity]
    assert_equal "Code looks good", result[:summary]
    assert_equal 1, result[:checks].length
    assert_equal "none", result[:action_required]
    assert_empty result[:fix_suggestions]
  end

  def test_parse_review_results_json_in_markdown_code_block
    json = <<~MD
      ```json
      {"overall_severity":"medium","summary":"Minor issues","checks":[],"action_required":"none","fix_suggestions":["Fix typo"]}
      ```
    MD

    result = Pipeline.parse_review_results(json, mock_logger)

    assert_equal "medium", result[:overall_severity]
    assert_equal "Minor issues", result[:summary]
    assert_equal ["Fix typo"], result[:fix_suggestions]
  end

  def test_parse_review_results_invalid_json_returns_warning
    logger = mock_logger
    logger.expects(:error).with(regexp_matches(/Error parseando/))

    result = Pipeline.parse_review_results("not valid json {{{", logger)

    assert_equal "warning", result[:overall_severity]
    assert_equal "none", result[:action_required]
    assert_empty result[:checks]
    assert_empty result[:fix_suggestions]
  end

  def test_parse_review_results_defaults_missing_fields
    json = JSON.generate({ "overall_severity" => "high", "summary" => "Issues found" })

    result = Pipeline.parse_review_results(json, mock_logger)

    assert_equal "high", result[:overall_severity]
    assert_empty result[:checks]
    assert_equal "none", result[:action_required]
    assert_empty result[:fix_suggestions]
  end

  # ─── format_review_comment ─────────────────────────────────────────

  def test_format_review_comment_with_pass_and_fail_checks
    review_result = {
      overall_severity: "medium",
      summary: "Some issues",
      checks: [
        { "name" => "security", "result" => "PASS", "severity" => "low", "details" => "OK" },
        { "name" => "performance", "result" => "FAIL", "severity" => "high", "details" => "Slow query" }
      ],
      fix_suggestions: []
    }

    comment = Pipeline.format_review_comment(review_result)

    assert_includes comment, "## Resultados de Revision de Codigo"
    assert_includes comment, "**Severidad general:** medium"
    assert_includes comment, "| security |"
    assert_includes comment, "| performance |"
    assert_includes comment, "PASS"
    assert_includes comment, "FAIL"
  end

  def test_format_review_comment_with_fix_suggestions
    review_result = {
      overall_severity: "high",
      summary: "Critical issues",
      checks: [],
      fix_suggestions: ["Fix SQL injection", "Add input validation"]
    }

    comment = Pipeline.format_review_comment(review_result)

    assert_includes comment, "### Sugerencias de correccion"
    assert_includes comment, "- Fix SQL injection"
    assert_includes comment, "- Add input validation"
  end

  def test_format_review_comment_empty_checks_no_table
    review_result = {
      overall_severity: "low",
      summary: "All good",
      checks: [],
      fix_suggestions: []
    }

    comment = Pipeline.format_review_comment(review_result)

    refute_includes comment, "| Criterio |"
    refute_includes comment, "### Sugerencias de correccion"
  end

  # ─── handle_review_fixes ───────────────────────────────────────────

  def test_handle_review_fixes_succeeds_first_attempt
    issue = build_github_issue
    logger = mock_logger

    initial_result = {
      action_required: "fix_and_rerun",
      fix_suggestions: ["Fix issue"],
      checks: [{ "name" => "security", "result" => "FAIL", "severity" => "high", "details" => "Bad" }]
    }

    # Fix succeeds
    Adw::Agent.stubs(:execute_template)
      .returns(build_agent_response(output: "fixed", success: true))
      .then
      .returns(build_agent_response(
        output: JSON.generate({
          "overall_severity" => "low",
          "summary" => "All fixed",
          "checks" => [{ "name" => "security", "result" => "PASS", "severity" => "low", "details" => "OK" }],
          "action_required" => "none",
          "fix_suggestions" => []
        }),
        success: true
      ))

    Adw::GitHub.stubs(:create_issue_comment).returns("456")

    result = Pipeline.handle_review_fixes(initial_result, "adw123", "42", issue, "plan.md", logger)

    assert_equal "none", result[:action_required]
    assert_equal "low", result[:overall_severity]
  end

  def test_handle_review_fixes_retries_up_to_max
    issue = build_github_issue
    logger = mock_logger

    initial_result = {
      action_required: "fix_and_rerun",
      fix_suggestions: ["Fix issue"],
      checks: [{ "name" => "security", "result" => "FAIL", "severity" => "high", "details" => "Bad" }]
    }

    # Both fix attempts succeed, but re-review always reports fix_and_rerun
    still_failing_json = JSON.generate({
      "overall_severity" => "high",
      "summary" => "Still failing",
      "checks" => [{ "name" => "security", "result" => "FAIL", "severity" => "high", "details" => "Still bad" }],
      "action_required" => "fix_and_rerun",
      "fix_suggestions" => ["Try again"]
    })

    Adw::Agent.stubs(:execute_template)
      .returns(build_agent_response(output: "fixed", success: true))
      .then.returns(build_agent_response(output: still_failing_json, success: true))
      .then.returns(build_agent_response(output: "fixed again", success: true))
      .then.returns(build_agent_response(output: still_failing_json, success: true))

    Adw::GitHub.stubs(:create_issue_comment).returns("456")

    result = Pipeline.handle_review_fixes(initial_result, "adw123", "42", issue, "plan.md", logger)

    # After MAX_REVIEW_FIX_ATTEMPTS (2), it should stop
    assert_equal "fix_and_rerun", result[:action_required]
    assert_equal "high", result[:overall_severity]
  end

  def test_handle_review_fixes_stops_on_fix_failure
    issue = build_github_issue
    logger = mock_logger

    initial_result = {
      action_required: "fix_and_rerun",
      fix_suggestions: ["Fix issue"],
      checks: [{ "name" => "security", "result" => "FAIL", "severity" => "high", "details" => "Bad" }]
    }

    # Fix fails
    Adw::Agent.stubs(:execute_template)
      .returns(build_agent_response(output: "fix failed", success: false))

    result = Pipeline.handle_review_fixes(initial_result, "adw123", "42", issue, "plan.md", logger)

    # Returns the original result unchanged
    assert_equal "fix_and_rerun", result[:action_required]
  end

  def test_handle_review_fixes_stops_on_recheck_failure
    issue = build_github_issue
    logger = mock_logger

    initial_result = {
      action_required: "fix_and_rerun",
      fix_suggestions: ["Fix issue"],
      checks: [{ "name" => "security", "result" => "FAIL", "severity" => "high", "details" => "Bad" }]
    }

    # Fix succeeds but re-review fails
    Adw::Agent.stubs(:execute_template)
      .returns(build_agent_response(output: "fixed", success: true))
      .then.returns(build_agent_response(output: "re-review error", success: false))

    result = Pipeline.handle_review_fixes(initial_result, "adw123", "42", issue, "plan.md", logger)

    assert_equal "fix_and_rerun", result[:action_required]
  end

  # ─── run_review ────────────────────────────────────────────────────

  def test_run_review_success_clean
    issue = build_github_issue
    tracker = build_tracker
    logger = mock_logger

    clean_review_json = JSON.generate({
      "overall_severity" => "low",
      "summary" => "All clear",
      "checks" => [{ "name" => "security", "result" => "PASS", "severity" => "low", "details" => "OK" }],
      "action_required" => "none",
      "fix_suggestions" => []
    })

    Adw::Agent.stubs(:execute_template)
      .returns(build_agent_response(output: clean_review_json, success: true))
    Adw::GitHub.stubs(:create_issue_comment).returns("789")
    Adw::Tracker.stubs(:set_phase_comment)
    Adw::Tracker.stubs(:save)

    result = Pipeline.run_review("adw123", "42", issue, tracker, logger)

    assert_equal "low", result[:overall_severity]
    assert_equal "none", result[:action_required]
  end

  def test_run_review_success_triggers_handle_review_fixes
    issue = build_github_issue
    tracker = build_tracker
    logger = mock_logger

    fix_needed_json = JSON.generate({
      "overall_severity" => "high",
      "summary" => "Issues found",
      "checks" => [{ "name" => "security", "result" => "FAIL", "severity" => "high", "details" => "SQL injection" }],
      "action_required" => "fix_and_rerun",
      "fix_suggestions" => ["Use parameterized queries"]
    })

    fixed_json = JSON.generate({
      "overall_severity" => "low",
      "summary" => "Fixed",
      "checks" => [{ "name" => "security", "result" => "PASS", "severity" => "low", "details" => "OK" }],
      "action_required" => "none",
      "fix_suggestions" => []
    })

    # First call: initial review returns fix_and_rerun
    # Second call: fix succeeds
    # Third call: re-review passes
    Adw::Agent.stubs(:execute_template)
      .returns(build_agent_response(output: fix_needed_json, success: true))
      .then.returns(build_agent_response(output: "fixed", success: true))
      .then.returns(build_agent_response(output: fixed_json, success: true))

    Adw::GitHub.stubs(:create_issue_comment).returns("789")
    Adw::Tracker.stubs(:set_phase_comment)
    Adw::Tracker.stubs(:save)

    result = Pipeline.run_review("adw123", "42", issue, tracker, logger)

    assert_equal "none", result[:action_required]
  end

  def test_run_review_failure_returns_error_hash
    issue = build_github_issue
    tracker = build_tracker
    logger = mock_logger

    Adw::Agent.stubs(:execute_template)
      .returns(build_agent_response(output: "agent error", success: false))

    result = Pipeline.run_review("adw123", "42", issue, tracker, logger)

    assert_equal "error", result[:overall_severity]
    assert_equal "none", result[:action_required]
  end

  # ─── run_issue_review ──────────────────────────────────────────────

  def test_run_issue_review_success_with_screenshots
    issue = build_github_issue
    tracker = build_tracker
    logger = mock_logger

    review_json = JSON.generate({
      "success" => true,
      "summary" => "Visual check passed",
      "plan_adherence" => { "result" => "PASS", "details" => "Matches plan" },
      "review_issues" => [],
      "screenshots" => [
        { "path" => "/tmp/screenshot1.png", "filename" => "screenshot1.png", "description" => "Home page" }
      ],
      "errors" => []
    })

    Adw::Agent.stubs(:execute_template)
      .returns(build_agent_response(output: review_json, success: true))

    uploaded_screenshots = [
      { "path" => "/tmp/screenshot1.png", "filename" => "screenshot1.png", "description" => "Home page", "url" => "https://cdn.example.com/screenshot1.png" }
    ]
    Adw::R2.stubs(:upload_evidence).returns(uploaded_screenshots)
    Adw::GitHub.stubs(:create_issue_comment).returns("999")
    Adw::Tracker.stubs(:set_phase_comment)
    Adw::Tracker.stubs(:save)

    result = Pipeline.run_issue_review("adw123", "42", issue, tracker, logger)

    assert result[:success]
    assert_equal "Visual check passed", result[:summary]
  end

  def test_run_issue_review_success_no_screenshots_warns
    issue = build_github_issue
    tracker = build_tracker
    logger = mock_logger

    review_json = JSON.generate({
      "success" => true,
      "summary" => "Check passed but no screenshots",
      "plan_adherence" => nil,
      "review_issues" => [],
      "screenshots" => [],
      "errors" => []
    })

    Adw::Agent.stubs(:execute_template)
      .returns(build_agent_response(output: review_json, success: true))

    logger.expects(:warn).with("No se obtuvieron screenshots")

    result = Pipeline.run_issue_review("adw123", "42", issue, tracker, logger)

    assert result[:success]
    assert_empty result[:screenshots]
  end

  def test_run_issue_review_failure_returns_nil
    issue = build_github_issue
    tracker = build_tracker
    logger = mock_logger

    Adw::Agent.stubs(:execute_template)
      .returns(build_agent_response(output: "review failed", success: false))
    Adw::GitHub.stubs(:create_issue_comment).returns("999")

    result = Pipeline.run_issue_review("adw123", "42", issue, tracker, logger)

    assert_nil result
  end

  def test_run_issue_review_r2_upload_fails_captures_error
    issue = build_github_issue
    tracker = build_tracker
    logger = mock_logger

    review_json = JSON.generate({
      "success" => true,
      "summary" => "Check passed",
      "plan_adherence" => nil,
      "review_issues" => [],
      "screenshots" => [
        { "path" => "/tmp/shot.png", "filename" => "shot.png", "description" => "Page" }
      ],
      "errors" => []
    })

    Adw::Agent.stubs(:execute_template)
      .returns(build_agent_response(output: review_json, success: true))

    Adw::R2.stubs(:upload_evidence).raises(Errno::ENOENT.new("file not found"))
    Adw::GitHub.stubs(:create_issue_comment).returns("999")
    Adw::Tracker.stubs(:set_phase_comment)
    Adw::Tracker.stubs(:save)

    result = Pipeline.run_issue_review("adw123", "42", issue, tracker, logger)

    assert_includes result[:errors], "R2 upload failed: No such file or directory - file not found"
  end

  # ─── run_documentation ─────────────────────────────────────────────

  def test_run_documentation_success
    tracker = build_tracker
    logger = mock_logger

    Adw::Agent.stubs(:execute_template)
      .returns(build_agent_response(output: "app_docs/feature.md\n", success: true))

    doc_content = <<~MD
      ## Overview
      This feature adds X.
      ## Que se Construyo
      Built Y.
      ## Other
      Details.
    MD
    File.stubs(:read).with("app_docs/feature.md").returns(doc_content)

    Adw::GitHub.stubs(:create_issue_comment).returns("1001")
    Adw::Tracker.stubs(:set_phase_comment)
    Adw::Tracker.stubs(:save)

    # Should not raise
    Pipeline.run_documentation("adw123", "42", tracker, logger)
  end

  def test_run_documentation_failure_warns
    tracker = build_tracker
    logger = mock_logger

    Adw::Agent.stubs(:execute_template)
      .returns(build_agent_response(output: "doc error", success: false))

    logger.expects(:warn).with(regexp_matches(/Generacion de documentacion fallo/))

    Pipeline.run_documentation("adw123", "42", tracker, logger)
  end

  # ─── post_documentation_summary ────────────────────────────────────

  def test_post_documentation_summary_with_overview_and_changes
    tracker = build_tracker
    logger = mock_logger

    doc_content = <<~MD
      ## Overview
      This feature provides a new login page.
      ## Que se Construyo
      Built authentication form with validation.
      ## Technical Details
      Uses bcrypt for hashing.
    MD

    File.stubs(:read).with("app_docs/feature.md").returns(doc_content)
    Adw::GitHub.expects(:create_issue_comment).with("42", regexp_matches(/Overview/)).returns("1001")
    Adw::Tracker.stubs(:set_phase_comment)
    Adw::Tracker.stubs(:save)

    Pipeline.post_documentation_summary("42", "adw123", "app_docs/feature.md", logger, tracker)
  end

  def test_post_documentation_summary_without_sections
    tracker = build_tracker
    logger = mock_logger

    doc_content = "Just some plain documentation content."

    File.stubs(:read).with("app_docs/plain.md").returns(doc_content)
    Adw::GitHub.expects(:create_issue_comment).with("42", regexp_matches(/Documentation Updated/)).returns("1002")
    Adw::Tracker.stubs(:set_phase_comment)
    Adw::Tracker.stubs(:save)

    Pipeline.post_documentation_summary("42", "adw123", "app_docs/plain.md", logger, tracker)
  end

  def test_post_documentation_summary_file_not_found_warns
    tracker = build_tracker
    logger = mock_logger

    File.stubs(:read).with("nonexistent.md").raises(Errno::ENOENT.new("nonexistent.md"))

    logger.expects(:warn).with(regexp_matches(/Could not post documentation summary/))

    Pipeline.post_documentation_summary("42", "adw123", "nonexistent.md", logger, tracker)
  end

  # ─── commit_all_changes ────────────────────────────────────────────

  def test_commit_all_changes_no_pending_changes_skips
    issue = build_github_issue
    tracker = build_tracker
    logger = mock_logger

    Open3.stubs(:capture3).with("git", "status", "--porcelain")
      .returns(["", "", mock_success_status])

    logger.expects(:info).with("No hay cambios pendientes para commit")

    Pipeline.commit_all_changes(issue, tracker, "adw123", "42", logger)
  end

  def test_commit_all_changes_with_pending_changes
    issue = build_github_issue
    tracker = build_tracker
    logger = mock_logger

    Open3.stubs(:capture3).with("git", "status", "--porcelain")
      .returns(["M app/models/user.rb\n", "", mock_success_status])

    Adw::Agent.expects(:execute_template).returns(build_agent_response(output: "committed", success: true))

    Pipeline.commit_all_changes(issue, tracker, "adw123", "42", logger)
  end

  def test_commit_all_changes_agent_failure_triggers_check_error
    issue = build_github_issue
    tracker = build_tracker
    logger = mock_logger

    Open3.stubs(:capture3).with("git", "status", "--porcelain")
      .returns(["M app/models/user.rb\n", "", mock_success_status])

    Adw::Agent.stubs(:execute_template)
      .returns(build_agent_response(output: "commit error", success: false))

    Adw::Tracker.stubs(:update)

    assert_raises(SystemExit) do
      Pipeline.commit_all_changes(issue, tracker, "adw123", "42", logger)
    end
  end

  # ─── create_pull_request ───────────────────────────────────────────

  def test_create_pull_request_success
    issue = build_github_issue
    tracker = build_tracker(branch_name: "feature/my-branch")
    logger = mock_logger

    Adw::Agent.expects(:execute_template).returns(
      build_agent_response(output: "https://github.com/test/repo/pull/1", success: true)
    )

    Pipeline.create_pull_request(tracker, issue, "adw123", "42", logger)
  end

  def test_create_pull_request_failure_triggers_check_error
    issue = build_github_issue
    tracker = build_tracker
    logger = mock_logger

    Adw::Agent.stubs(:execute_template)
      .returns(build_agent_response(output: "PR error", success: false))

    Adw::Tracker.stubs(:update)

    assert_raises(SystemExit) do
      Pipeline.create_pull_request(tracker, issue, "adw123", "42", logger)
    end
  end

  # ─── log_test_results ──────────────────────────────────────────────

  def test_log_test_results_with_failures
    tracker = build_tracker
    logger = mock_logger

    results = [
      build_test_result(test_name: "test_login", passed: true),
      build_test_result(test_name: "test_signup", passed: false, error: "Expected 200 but got 500")
    ]

    Adw::GitHub.expects(:create_issue_comment).with("42", regexp_matches(/1 passed.*1 failed/m)).returns("555")
    Adw::Tracker.stubs(:set_phase_comment)
    Adw::Tracker.stubs(:save)

    Pipeline.log_test_results("42", "adw123", results, 1, 1, logger, tracker)
  end

  def test_log_test_results_all_passed
    tracker = build_tracker
    logger = mock_logger

    results = [
      build_test_result(test_name: "test_login", passed: true),
      build_test_result(test_name: "test_signup", passed: true)
    ]

    Adw::GitHub.expects(:create_issue_comment).with("42", regexp_matches(/2 passed/)).returns("555")
    Adw::Tracker.stubs(:set_phase_comment)
    Adw::Tracker.stubs(:save)

    Pipeline.log_test_results("42", "adw123", results, 2, 0, logger, tracker)
  end

  # ─── main flow ─────────────────────────────────────────────────────

  # Shared setup for main flow tests. Stubs ARGV, logger, Process.spawn/wait2
  # (successful plan_build), tracker loading, and issue loading.
  # Returns [issue, tracker, logger].
  def stub_main_pipeline(plan_build_success: true)
    issue = build_github_issue
    tracker = build_tracker
    logger = mock_logger

    ARGV.replace(["42", "adw123"])
    Adw::Utils.stubs(:setup_logger).returns(logger)

    Process.stubs(:spawn).returns(12345)
    status = mock("plan_build_status")
    status.stubs(:success?).returns(plan_build_success)
    status.stubs(:exitstatus).returns(plan_build_success ? 0 : 1)
    Process.stubs(:wait2).with(12345).returns([12345, status])

    if plan_build_success
      Adw::Tracker.stubs(:load).returns(tracker)
      Adw::GitHub.stubs(:extract_repo_path).returns("test/repo")
      Adw::GitHub.stubs(:repo_url).returns("https://github.com/test/repo")
      Adw::GitHub.stubs(:fetch_issue).returns(issue)
      Adw::Tracker.stubs(:update)
      Adw::GitHub.stubs(:create_issue_comment).returns("999")
      Adw::Tracker.stubs(:set_phase_comment)
      Adw::Tracker.stubs(:save)
    end

    [issue, tracker, logger]
  end

  def test_main_happy_path
    _issue, _tracker, _logger = stub_main_pipeline

    Pipeline.stubs(:run_tests_with_resolution).returns([[], 5, 0])

    clean_review = {
      overall_severity: "low",
      summary: "All good",
      checks: [],
      action_required: "none",
      fix_suggestions: []
    }
    Pipeline.stubs(:run_review).returns(clean_review)
    Pipeline.stubs(:run_issue_review).returns({ success: true })
    Pipeline.stubs(:run_documentation)
    Pipeline.stubs(:commit_all_changes)
    Pipeline.stubs(:create_pull_request)

    Pipeline.main
  ensure
    ARGV.replace([])
  end

  def test_main_plan_build_fails_exits_early
    stub_main_pipeline(plan_build_success: false)

    assert_raises(SystemExit) do
      Pipeline.main
    end
  ensure
    ARGV.replace([])
  end

  def test_main_tests_fail_sets_error_and_exits
    _issue, tracker, logger = stub_main_pipeline

    failed_test = build_test_result(test_name: "test_broken", passed: false, error: "assertion failed")
    Pipeline.stubs(:run_tests_with_resolution).returns([[failed_test], 0, 1])

    Adw::Tracker.expects(:update).with(tracker, "42", "error", logger)

    assert_raises(SystemExit) do
      Pipeline.main
    end
  ensure
    ARGV.replace([])
  end

  def test_main_review_critical_unresolvable_sets_error_and_exits
    _issue, tracker, logger = stub_main_pipeline

    Pipeline.stubs(:run_tests_with_resolution).returns([[], 5, 0])

    critical_review = {
      overall_severity: "critical",
      summary: "Critical security issue",
      checks: [],
      action_required: "fix_and_rerun",
      fix_suggestions: ["Cannot be auto-fixed"]
    }
    Pipeline.stubs(:run_review).returns(critical_review)

    Adw::Tracker.expects(:update).with(tracker, "42", "error", logger)

    assert_raises(SystemExit) do
      Pipeline.main
    end
  ensure
    ARGV.replace([])
  end
end
