# frozen_string_literal: true

require_relative "../../test_helper"

class PipelineHelpersTest < Minitest::Test
  include Adw::PipelineHelpers
  include Factories

  # ── format_issue_message ──

  def test_format_issue_message_without_session_id
    result = format_issue_message("adw12345", "builder", "Build complete")
    assert_equal "adw12345_builder: Build complete", result
  end

  def test_format_issue_message_with_session_id
    result = format_issue_message("adw12345", "builder", "Build complete", "sess99")
    assert_equal "adw12345_builder_sess99: Build complete", result
  end

  # ── extract_json_from_markdown ──

  def test_extract_json_plain_string
    json = '{"key": "value"}'
    assert_equal json, extract_json_from_markdown(json)
  end

  def test_extract_json_wrapped_in_json_code_block
    input = "```json\n{\"key\": \"value\"}\n```"
    assert_equal '{"key": "value"}', extract_json_from_markdown(input)
  end

  def test_extract_json_wrapped_in_plain_code_block
    input = "```\n{\"key\": \"value\"}\n```"
    assert_equal '{"key": "value"}', extract_json_from_markdown(input)
  end

  def test_extract_json_with_extra_whitespace
    input = "  \n ```json\n  {\"key\": \"value\"}  \n ```  \n "
    assert_equal '{"key": "value"}', extract_json_from_markdown(input)
  end

  # ── parse_test_results ──

  def test_parse_test_results_valid_json_array
    json = JSON.generate([
      test_result_hash(test_name: "test1", passed: true),
      test_result_hash(test_name: "test2", passed: false, error: "fail")
    ])
    logger = mock("logger")

    results, passed, failed = parse_test_results(json, logger)
    assert_equal 2, results.length
    assert_equal 1, passed
    assert_equal 1, failed
    assert_instance_of Adw::TestResult, results.first
  end

  def test_parse_test_results_json_wrapped_in_markdown
    json = "```json\n#{JSON.generate([test_result_hash])}\n```"
    logger = mock("logger")

    results, passed, failed = parse_test_results(json, logger)
    assert_equal 1, results.length
    assert_equal 1, passed
    assert_equal 0, failed
  end

  def test_parse_test_results_invalid_json
    logger = mock("logger")
    logger.expects(:error).once

    results, passed, failed = parse_test_results("not json", logger)
    assert_equal [], results
    assert_equal 0, passed
    assert_equal 0, failed
  end

  def test_parse_test_results_creates_correct_test_result_objects
    json = JSON.generate([test_result_hash(test_name: "my_test", passed: false, error: "boom")])
    logger = mock("logger")

    results, _passed, _failed = parse_test_results(json, logger)
    tr = results.first
    assert_equal "my_test", tr.test_name
    assert_equal false, tr.passed
    assert_equal "boom", tr.error
  end

  def test_parse_test_results_mix_of_passed_and_failed
    json = JSON.generate([
      test_result_hash(test_name: "a", passed: true),
      test_result_hash(test_name: "b", passed: false),
      test_result_hash(test_name: "c", passed: true),
      test_result_hash(test_name: "d", passed: false)
    ])
    logger = mock("logger")

    _results, passed, failed = parse_test_results(json, logger)
    assert_equal 2, passed
    assert_equal 2, failed
  end

  # ── check_error ──

  def test_check_error_with_failed_response_exits
    response = build_agent_prompt_response(success: false, output: "Something went wrong")
    logger = mock("logger")
    logger.expects(:error).with(includes("Something went wrong"))
    tracker = { status: "testing", adw_id: "x" }
    Adw::Tracker.expects(:update).with(tracker, 1, "error", logger)

    assert_raises(SystemExit) do
      check_error(response, 1, "Test failed", logger, tracker)
    end
  end

  def test_check_error_with_successful_response_is_noop
    response = build_agent_prompt_response(success: true, output: "All good")
    logger = mock("logger")
    tracker = { status: "testing", adw_id: "x" }

    result = check_error(response, 1, "prefix", logger, tracker)
    assert_nil result
  end

  def test_check_error_with_string_error_exits
    logger = mock("logger")
    logger.expects(:error).with(includes("bad stuff"))
    tracker = { status: "testing", adw_id: "x" }
    Adw::Tracker.expects(:update).with(tracker, 1, "error", logger)

    assert_raises(SystemExit) do
      check_error("bad stuff", 1, "prefix", logger, tracker)
    end
  end

  def test_check_error_with_nil_is_noop
    logger = mock("logger")
    tracker = { status: "testing", adw_id: "x" }

    result = check_error(nil, 1, "prefix", logger, tracker)
    assert_nil result
  end

  # ── bot_comment? ──

  def test_bot_comment_matches_pattern
    assert bot_comment?("abc12345_agent: some message")
  end

  def test_bot_comment_normal_comment_is_falsy
    refute bot_comment?("Just a normal comment")
  end

  def test_bot_comment_empty_string_is_falsy
    refute bot_comment?("")
  end

  # ── format_evidence_comment ──

  def test_format_evidence_comment_with_screenshot_urls
    result = {
      summary: "Looks good",
      plan_adherence: { "result" => "PASS", "details" => "All items done" },
      screenshots: [
        { "description" => "Home page", "filename" => "home.png", "url" => "https://r2.example.com/home.png", "path" => "/tmp/home.png" }
      ],
      review_issues: [],
      errors: []
    }
    comment = format_evidence_comment(result)

    assert_includes comment, "Evidencia Visual"
    assert_includes comment, "![home.png](https://r2.example.com/home.png)"
    assert_includes comment, "Looks good"
    refute_includes comment, "no se pudieron subir"
  end

  def test_format_evidence_comment_without_screenshot_urls
    result = {
      summary: "Looks ok",
      plan_adherence: nil,
      screenshots: [
        { "description" => "Page", "filename" => "page.png", "path" => "/tmp/page.png" }
      ],
      review_issues: [],
      errors: []
    }
    comment = format_evidence_comment(result)

    assert_includes comment, "no se pudieron subir"
    assert_includes comment, "/tmp/page.png"
  end

  def test_format_evidence_comment_with_review_issues_and_screenshot_urls
    result = {
      summary: "Found issues",
      plan_adherence: nil,
      screenshots: [],
      review_issues: [
        { "description" => "Button misaligned", "severity" => "blocker", "resolution" => "Fix CSS", "screenshot_url" => "https://r2.example.com/btn.png" }
      ],
      errors: []
    }
    comment = format_evidence_comment(result)

    assert_includes comment, "Problemas encontrados"
    assert_includes comment, "Button misaligned"
    assert_includes comment, "blocker"
    assert_includes comment, "![evidencia](https://r2.example.com/btn.png)"
  end

  def test_format_evidence_comment_plan_adherence_pass
    result = {
      summary: "OK",
      plan_adherence: { "result" => "PASS", "details" => "Good" },
      screenshots: [],
      review_issues: [],
      errors: []
    }
    comment = format_evidence_comment(result)
    # The PASS emoji is a checkmark
    assert_match(/PASS/, comment)
  end

  def test_format_evidence_comment_plan_adherence_fail
    result = {
      summary: "Not OK",
      plan_adherence: { "result" => "FAIL", "details" => "Missing items" },
      screenshots: [],
      review_issues: [],
      errors: []
    }
    comment = format_evidence_comment(result)
    assert_match(/FAIL/, comment)
  end

  def test_format_evidence_comment_with_errors
    result = {
      summary: "Error occurred",
      plan_adherence: nil,
      screenshots: [],
      review_issues: [],
      errors: ["Timeout on page load", "Element not found"]
    }
    comment = format_evidence_comment(result)

    assert_includes comment, "Errores"
    assert_includes comment, "Timeout on page load"
    assert_includes comment, "Element not found"
  end

  def test_format_evidence_comment_empty_screenshots
    result = {
      summary: "Nothing to show",
      plan_adherence: nil,
      screenshots: [],
      review_issues: [],
      errors: []
    }
    comment = format_evidence_comment(result)

    assert_includes comment, "Evidencia Visual"
    assert_includes comment, "Nothing to show"
  end

  # ── link_screenshot_urls ──

  def test_link_screenshot_urls_links_correctly
    screenshots = [
      { "path" => "/tmp/home.png", "url" => "https://r2.example.com/home.png" },
      { "path" => "/tmp/login.png", "url" => "https://r2.example.com/login.png" }
    ]
    review_issues = [
      { "description" => "Issue 1", "screenshot_path" => "/tmp/home.png" },
      { "description" => "Issue 2", "screenshot_path" => "/tmp/login.png" }
    ]

    link_screenshot_urls(screenshots, review_issues)

    assert_equal "https://r2.example.com/home.png", review_issues[0]["screenshot_url"]
    assert_equal "https://r2.example.com/login.png", review_issues[1]["screenshot_url"]
  end

  def test_link_screenshot_urls_no_review_issues
    screenshots = [{ "path" => "/tmp/a.png", "url" => "https://r2.example.com/a.png" }]
    # Should not raise
    link_screenshot_urls(screenshots, nil)
    link_screenshot_urls(screenshots, [])
  end

  def test_link_screenshot_urls_screenshots_without_url
    screenshots = [{ "path" => "/tmp/a.png" }]
    review_issues = [{ "description" => "Issue", "screenshot_path" => "/tmp/a.png" }]

    link_screenshot_urls(screenshots, review_issues)

    assert_nil review_issues[0]["screenshot_url"]
  end

  # ── plan_path_for ──

  def test_plan_path_for
    assert_equal ".issues/42/plan.md", plan_path_for(42)
  end

  def test_plan_path_for_string_number
    assert_equal ".issues/7/plan.md", plan_path_for(7)
  end

  # ── parse_issue_review_results ──

  def test_parse_issue_review_results_valid_json
    data = {
      "success" => true,
      "summary" => "All good",
      "plan_adherence" => { "result" => "PASS", "details" => "OK" },
      "review_issues" => [{ "description" => "Minor thing" }],
      "screenshots" => [{ "path" => "/tmp/s.png" }],
      "errors" => []
    }
    logger = mock("logger")

    result = parse_issue_review_results(JSON.generate(data), logger)

    assert_equal true, result[:success]
    assert_equal "All good", result[:summary]
    assert_equal "PASS", result[:plan_adherence]["result"]
    assert_equal 1, result[:review_issues].length
    assert_equal 1, result[:screenshots].length
    assert_equal [], result[:errors]
  end

  def test_parse_issue_review_results_invalid_json
    logger = mock("logger")
    logger.expects(:error).once

    result = parse_issue_review_results("not valid json", logger)

    assert_equal false, result[:success]
    assert_includes result[:summary], "No se pudieron parsear"
    assert_equal [], result[:review_issues]
    assert_equal [], result[:screenshots]
    assert result[:errors].any? { |e| e.include?("JSON parse error") }
  end

  def test_parse_issue_review_results_missing_optional_fields
    data = { "success" => true, "summary" => "OK", "plan_adherence" => nil }
    logger = mock("logger")

    result = parse_issue_review_results(JSON.generate(data), logger)

    assert_equal true, result[:success]
    assert_equal [], result[:review_issues]
    assert_equal [], result[:screenshots]
    assert_equal [], result[:errors]
  end

  # ── run_tests (mock Agent.execute_template) ──

  def test_run_tests_creates_correct_request
    logger = mock("logger")
    logger.stubs(:debug)

    Adw.stubs(:project_root).returns("/project")

    expected_response = build_agent_prompt_response(output: "[]", success: true)
    Adw::Agent.expects(:execute_template).with do |req|
      assert_instance_of Adw::AgentTemplateRequest, req
      assert_equal "test_runner", req.agent_name
      assert_equal "/adw:test", req.slash_command
      assert_equal 42, req.issue_number
      assert_equal "abc12345", req.adw_id
      assert_equal "sonnet", req.model
      true
    end.returns(expected_response)

    response = run_tests(42, "abc12345", logger)
    assert_equal expected_response, response
  end

  # ── resolve_failed_tests ──

  def test_resolve_failed_tests_single_success
    failed_test = build_test_result(test_name: "test_fail", passed: false, error: "err")
    logger = mock("logger")
    logger.stubs(:info)

    success_response = build_agent_prompt_response(success: true, output: "fixed")

    Adw::GitHub.stubs(:create_issue_comment)
    Adw::Agent.expects(:execute_template).returns(success_response)

    resolved, unresolved = resolve_failed_tests(
      [failed_test], "adw123", 1, logger,
      verbose_comments: false, iteration: 1
    )

    assert_equal 1, resolved
    assert_equal 0, unresolved
  end

  def test_resolve_failed_tests_single_failure
    failed_test = build_test_result(test_name: "test_fail", passed: false, error: "err")
    logger = mock("logger")
    logger.stubs(:info)
    logger.stubs(:error)

    fail_response = build_agent_prompt_response(success: false, output: "cant fix")

    Adw::GitHub.stubs(:create_issue_comment)
    Adw::Agent.expects(:execute_template).returns(fail_response)

    resolved, unresolved = resolve_failed_tests(
      [failed_test], "adw123", 1, logger,
      verbose_comments: false, iteration: 1
    )

    assert_equal 0, resolved
    assert_equal 1, unresolved
  end

  def test_resolve_failed_tests_multiple
    tests = [
      build_test_result(test_name: "test1", passed: false, error: "e1"),
      build_test_result(test_name: "test2", passed: false, error: "e2")
    ]
    logger = mock("logger")
    logger.stubs(:info)
    logger.stubs(:error)

    Adw::GitHub.stubs(:create_issue_comment)
    Adw::Agent.expects(:execute_template).twice
              .returns(build_agent_prompt_response(success: true, output: "ok"))
              .then.returns(build_agent_prompt_response(success: false, output: "nope"))

    resolved, unresolved = resolve_failed_tests(
      tests, "adw123", 1, logger,
      verbose_comments: false, iteration: 2
    )

    assert_equal 1, resolved
    assert_equal 1, unresolved
  end

  def test_resolve_failed_tests_agent_names_include_iteration_and_index
    failed_test = build_test_result(test_name: "test_x", passed: false, error: "e")
    logger = mock("logger")
    logger.stubs(:info)

    Adw::GitHub.stubs(:create_issue_comment)
    Adw::Agent.expects(:execute_template).with do |req|
      assert_equal "test_resolver_iter3_0", req.agent_name
      true
    end.returns(build_agent_prompt_response(success: true, output: "ok"))

    resolve_failed_tests(
      [failed_test], "adw123", 1, logger,
      agent_prefix: "test_resolver", verbose_comments: false, iteration: 3
    )
  end

  def test_resolve_failed_tests_verbose_comments_creates_github_comments
    failed_test = build_test_result(test_name: "test_v", passed: false, error: "e")
    logger = mock("logger")
    logger.stubs(:info)

    # Expects 2 comments: one before resolve attempt, one after success
    Adw::GitHub.expects(:create_issue_comment).times(2)
    Adw::Agent.expects(:execute_template)
              .returns(build_agent_prompt_response(success: true, output: "ok"))

    resolve_failed_tests(
      [failed_test], "adw123", 1, logger,
      verbose_comments: true, iteration: 1
    )
  end

  def test_resolve_failed_tests_verbose_false_skips_success_failure_comments
    failed_test = build_test_result(test_name: "test_v", passed: false, error: "e")
    logger = mock("logger")
    logger.stubs(:info)

    # Only the initial "Intentando resolver" comment is always created
    Adw::GitHub.expects(:create_issue_comment).times(1)
    Adw::Agent.expects(:execute_template)
              .returns(build_agent_prompt_response(success: true, output: "ok"))

    resolve_failed_tests(
      [failed_test], "adw123", 1, logger,
      verbose_comments: false, iteration: 1
    )
  end

  # ── run_tests_with_resolution ──

  def test_run_tests_with_resolution_all_pass
    logger = mock("logger")
    logger.stubs(:info)
    logger.stubs(:debug)

    Adw.stubs(:project_root).returns("/project")

    all_pass = JSON.generate([test_result_hash(passed: true)])
    test_response = build_agent_prompt_response(output: all_pass, success: true)
    Adw::Agent.expects(:execute_template).returns(test_response)

    results, passed, failed = run_tests_with_resolution("adw123", 1, logger, verbose_comments: false)

    assert_equal 1, results.length
    assert_equal 1, passed
    assert_equal 0, failed
  end

  def test_run_tests_with_resolution_failures_then_resolved
    logger = mock("logger")
    logger.stubs(:info)
    logger.stubs(:debug)
    logger.stubs(:error)

    Adw.stubs(:project_root).returns("/project")
    Adw::GitHub.stubs(:create_issue_comment)

    fail_json = JSON.generate([test_result_hash(test_name: "t1", passed: false, error: "e")])
    pass_json = JSON.generate([test_result_hash(test_name: "t1", passed: true)])

    fail_response = build_agent_prompt_response(output: fail_json, success: true)
    pass_response = build_agent_prompt_response(output: pass_json, success: true)
    resolve_response = build_agent_prompt_response(output: "fixed", success: true)

    # First run fails, resolve succeeds, second run passes
    Adw::Agent.expects(:execute_template).times(3)
              .returns(fail_response)
              .then.returns(resolve_response)
              .then.returns(pass_response)

    results, passed, failed = run_tests_with_resolution("adw123", 1, logger, verbose_comments: false)

    assert_equal 1, results.length
    assert_equal 1, passed
    assert_equal 0, failed
  end

  def test_run_tests_with_resolution_max_attempts
    logger = mock("logger")
    logger.stubs(:info)
    logger.stubs(:debug)
    logger.stubs(:warn)
    logger.stubs(:error)

    Adw.stubs(:project_root).returns("/project")
    Adw::GitHub.stubs(:create_issue_comment)

    fail_json = JSON.generate([test_result_hash(test_name: "t1", passed: false, error: "e")])
    fail_response = build_agent_prompt_response(output: fail_json, success: true)
    resolve_response = build_agent_prompt_response(output: "tried", success: true)

    # Each iteration: run_tests + resolve = 2 calls. 4 iterations but last one doesn't resolve.
    # Iteration 1: run_tests(fail) + resolve(success) = 2
    # Iteration 2: run_tests(fail) + resolve(success) = 2
    # Iteration 3: run_tests(fail) + resolve(success) = 2
    # Iteration 4: run_tests(fail) = 1 (max reached, no resolve)
    Adw::Agent.expects(:execute_template).times(7)
              .returns(fail_response)   # iter 1 test
              .then.returns(resolve_response) # iter 1 resolve
              .then.returns(fail_response)   # iter 2 test
              .then.returns(resolve_response) # iter 2 resolve
              .then.returns(fail_response)   # iter 3 test
              .then.returns(resolve_response) # iter 3 resolve
              .then.returns(fail_response)   # iter 4 test (max, stops)

    results, passed, failed = run_tests_with_resolution("adw123", 1, logger, verbose_comments: false)

    assert_equal 1, results.length
    assert_equal 0, passed
    assert_equal 1, failed
  end

  def test_run_tests_with_resolution_no_tests_resolved_stops_early
    logger = mock("logger")
    logger.stubs(:info)
    logger.stubs(:debug)
    logger.stubs(:error)

    Adw.stubs(:project_root).returns("/project")
    Adw::GitHub.stubs(:create_issue_comment)

    fail_json = JSON.generate([test_result_hash(test_name: "t1", passed: false, error: "e")])
    fail_response = build_agent_prompt_response(output: fail_json, success: true)
    resolve_fail_response = build_agent_prompt_response(output: "nope", success: false)

    # run_tests(fail) + resolve(fail) = 2 calls total, then stops
    Adw::Agent.expects(:execute_template).times(2)
              .returns(fail_response)
              .then.returns(resolve_fail_response)

    results, passed, failed = run_tests_with_resolution("adw123", 1, logger, verbose_comments: false)

    assert_equal 1, results.length
    assert_equal 0, passed
    assert_equal 1, failed
  end

  # ── post_plan_comment ──

  def test_post_plan_comment_success
    logger = mock("logger")
    logger.expects(:info).once

    File.expects(:read).with("/path/to/plan.md").returns("# Plan content")
    Adw::GitHub.expects(:create_issue_comment).returns("comment-999")

    comment_id = post_plan_comment(1, "adw123", "planner", "/path/to/plan.md", "Implementation Plan", logger)

    assert_equal "comment-999", comment_id
  end

  def test_post_plan_comment_file_not_found
    logger = mock("logger")
    logger.expects(:warn).once

    File.expects(:read).with("/missing/plan.md").raises(Errno::ENOENT.new("No such file"))

    result = post_plan_comment(1, "adw123", "planner", "/missing/plan.md", "Plan", logger)
    assert_nil result
  end
end
