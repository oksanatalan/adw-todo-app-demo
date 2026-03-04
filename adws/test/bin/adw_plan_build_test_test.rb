# frozen_string_literal: true

require_relative "../test_helper"
load File.expand_path("../../bin/adw_plan_build_test", __dir__)

class AdwPlanBuildTestTest < Minitest::Test
  include Factories

  PBT = Adw::Pipelines::PlanBuildTest

  def setup
    @logger = build_mock_logger
    @adw_id = "abc12345"
    @issue_number = 42
  end

  # ──────────────────────────────────────────────
  # format_issue_message
  # ──────────────────────────────────────────────

  def test_format_issue_message_without_session_id
    result = PBT.format_issue_message("abc12345", "agent_name", "hello world")
    assert_equal "abc12345_agent_name: hello world", result
  end

  def test_format_issue_message_with_session_id
    result = PBT.format_issue_message("abc12345", "agent_name", "hello world", "sess1")
    assert_equal "abc12345_agent_name_sess1: hello world", result
  end

  def test_format_issue_message_with_nil_session_id
    result = PBT.format_issue_message("abc12345", "agent_name", "hello world", nil)
    assert_equal "abc12345_agent_name: hello world", result
  end

  # ──────────────────────────────────────────────
  # run_tests
  # ──────────────────────────────────────────────

  def test_run_tests_creates_correct_request_and_returns_response
    expected_response = build_agent_prompt_response(output: "[]", success: true)

    Adw::Agent.expects(:execute_template).with do |req|
      req.slash_command == "/adw:test" &&
        req.agent_name == "test_runner" &&
        req.model == "sonnet" &&
        req.issue_number == @issue_number &&
        req.adw_id == @adw_id
    end.returns(expected_response)

    response = PBT.run_tests(@issue_number, @adw_id, @logger)
    assert_equal expected_response, response
  end

  def test_run_tests_log_dir_includes_issue_number_and_adw_id
    expected_response = build_agent_prompt_response
    log_dir_pattern = File.join(Adw.project_root, ".issues", @issue_number.to_s, "logs", @adw_id, "test_runner")

    Adw::Agent.expects(:execute_template).with do |req|
      req.args.first == log_dir_pattern
    end.returns(expected_response)

    PBT.run_tests(@issue_number, @adw_id, @logger)
  end

  # ──────────────────────────────────────────────
  # parse_test_results
  # ──────────────────────────────────────────────

  def test_parse_test_results_valid_json_array
    tests = [
      { test_name: "test_a", passed: true, execution_command: "cmd", test_purpose: "purpose" },
      { test_name: "test_b", passed: false, execution_command: "cmd", test_purpose: "purpose", error: "fail" }
    ]
    json = JSON.generate(tests)

    results, passed, failed = PBT.parse_test_results(json, @logger)

    assert_equal 2, results.length
    assert_equal 1, passed
    assert_equal 1, failed
    assert results[0].passed
    refute results[1].passed
  end

  def test_parse_test_results_json_wrapped_in_markdown
    tests = [
      { test_name: "test_a", passed: true, execution_command: "cmd", test_purpose: "purpose" }
    ]
    json = "```json\n#{JSON.generate(tests)}\n```"

    results, passed, failed = PBT.parse_test_results(json, @logger)

    assert_equal 1, results.length
    assert_equal 1, passed
    assert_equal 0, failed
  end

  def test_parse_test_results_markdown_without_json_hint
    tests = [
      { test_name: "test_a", passed: true, execution_command: "cmd", test_purpose: "purpose" }
    ]
    json = "```\n#{JSON.generate(tests)}\n```"

    results, passed, failed = PBT.parse_test_results(json, @logger)

    assert_equal 1, results.length
    assert_equal 1, passed
    assert_equal 0, failed
  end

  def test_parse_test_results_invalid_json
    results, passed, failed = PBT.parse_test_results("not json at all", @logger)

    assert_equal [], results
    assert_equal 0, passed
    assert_equal 0, failed
  end

  def test_parse_test_results_mixed_pass_fail
    tests = [
      { test_name: "t1", passed: true, execution_command: "c", test_purpose: "p" },
      { test_name: "t2", passed: false, execution_command: "c", test_purpose: "p", error: "e" },
      { test_name: "t3", passed: true, execution_command: "c", test_purpose: "p" },
      { test_name: "t4", passed: false, execution_command: "c", test_purpose: "p", error: "e" },
      { test_name: "t5", passed: true, execution_command: "c", test_purpose: "p" }
    ]
    json = JSON.generate(tests)

    results, passed, failed = PBT.parse_test_results(json, @logger)

    assert_equal 5, results.length
    assert_equal 3, passed
    assert_equal 2, failed
  end

  # ──────────────────────────────────────────────
  # resolve_failed_tests
  # ──────────────────────────────────────────────

  def test_resolve_failed_tests_one_test_resolve_succeeds
    failed = [build_failing_test("test_broken")]
    success_response = build_agent_prompt_response(success: true)

    Adw::Agent.expects(:execute_template).returns(success_response)
    Adw::GitHub.expects(:create_issue_comment).times(2) # attempt + success

    resolved, unresolved = PBT.resolve_failed_tests(failed, @adw_id, @issue_number, @logger)

    assert_equal 1, resolved
    assert_equal 0, unresolved
  end

  def test_resolve_failed_tests_one_test_resolve_fails
    failed = [build_failing_test("test_broken")]
    fail_response = build_agent_prompt_response(success: false, output: "could not fix")

    Adw::Agent.expects(:execute_template).returns(fail_response)
    Adw::GitHub.expects(:create_issue_comment).times(2) # attempt + failure

    resolved, unresolved = PBT.resolve_failed_tests(failed, @adw_id, @issue_number, @logger)

    assert_equal 0, resolved
    assert_equal 1, unresolved
  end

  def test_resolve_failed_tests_multiple_tests_mixed
    failed = [
      build_failing_test("test_a"),
      build_failing_test("test_b"),
      build_failing_test("test_c")
    ]

    success_response = build_agent_prompt_response(success: true)
    fail_response = build_agent_prompt_response(success: false, output: "nope")

    Adw::Agent.expects(:execute_template).times(3)
      .returns(success_response)
      .then.returns(fail_response)
      .then.returns(success_response)

    # 3 attempt comments + 2 success comments + 1 failure comment = 6
    Adw::GitHub.expects(:create_issue_comment).times(6)

    resolved, unresolved = PBT.resolve_failed_tests(failed, @adw_id, @issue_number, @logger)

    assert_equal 2, resolved
    assert_equal 1, unresolved
  end

  def test_resolve_failed_tests_agent_name_includes_iteration_and_index
    failed = [build_failing_test("test_x")]
    success_response = build_agent_prompt_response(success: true)

    Adw::Agent.expects(:execute_template).with do |req|
      req.agent_name == "test_resolver_iter3_0"
    end.returns(success_response)

    Adw::GitHub.stubs(:create_issue_comment)

    PBT.resolve_failed_tests(failed, @adw_id, @issue_number, @logger, iteration: 3)
  end

  def test_resolve_failed_tests_creates_github_comment_for_each
    failed = [build_failing_test("test_one"), build_failing_test("test_two")]
    success_response = build_agent_prompt_response(success: true)

    Adw::Agent.stubs(:execute_template).returns(success_response)

    comment_bodies = []
    Adw::GitHub.stubs(:create_issue_comment).with do |_issue, body|
      comment_bodies << body
      true
    end

    PBT.resolve_failed_tests(failed, @adw_id, @issue_number, @logger)

    # Each test gets an "attempting" and a "resolved" comment
    assert_equal 4, comment_bodies.length
    assert comment_bodies[0].include?("Intentando resolver: test_one")
    assert comment_bodies[1].include?("Resuelto correctamente: test_one")
    assert comment_bodies[2].include?("Intentando resolver: test_two")
    assert comment_bodies[3].include?("Resuelto correctamente: test_two")
  end

  # ──────────────────────────────────────────────
  # run_tests_with_resolution (retry loop)
  # ──────────────────────────────────────────────

  def test_run_tests_with_resolution_all_pass_first_try
    passing_results = [
      { test_name: "t1", passed: true, execution_command: "c", test_purpose: "p" }
    ]
    response = build_agent_prompt_response(output: JSON.generate(passing_results), success: true)

    Adw::Agent.expects(:execute_template).once.returns(response)
    Adw::GitHub.stubs(:create_issue_comment)

    results, passed, failed = PBT.run_tests_with_resolution(@adw_id, @issue_number, @logger)

    assert_equal 1, results.length
    assert_equal 1, passed
    assert_equal 0, failed
  end

  def test_run_tests_with_resolution_fail_then_resolve_then_pass
    failing_results = [
      { test_name: "t1", passed: false, execution_command: "c", test_purpose: "p", error: "err" }
    ]
    passing_results = [
      { test_name: "t1", passed: true, execution_command: "c", test_purpose: "p" }
    ]

    fail_response = build_agent_prompt_response(output: JSON.generate(failing_results), success: true)
    pass_response = build_agent_prompt_response(output: JSON.generate(passing_results), success: true)
    resolve_response = build_agent_prompt_response(success: true)

    agent_calls = sequence("agent_calls")
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(fail_response)  # run_tests attempt 1
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(resolve_response) # resolve
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(pass_response)   # run_tests attempt 2

    Adw::GitHub.stubs(:create_issue_comment)

    results, passed, failed = PBT.run_tests_with_resolution(@adw_id, @issue_number, @logger)

    assert_equal 1, results.length
    assert_equal 1, passed
    assert_equal 0, failed
  end

  def test_run_tests_with_resolution_fail_resolve_fail_resolve_pass
    failing_results = [
      { test_name: "t1", passed: false, execution_command: "c", test_purpose: "p", error: "err" }
    ]
    passing_results = [
      { test_name: "t1", passed: true, execution_command: "c", test_purpose: "p" }
    ]

    fail_response = build_agent_prompt_response(output: JSON.generate(failing_results), success: true)
    pass_response = build_agent_prompt_response(output: JSON.generate(passing_results), success: true)
    resolve_response = build_agent_prompt_response(success: true)

    agent_calls = sequence("agent_calls")
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(fail_response)    # attempt 1: tests fail
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(resolve_response)  # resolve attempt 1
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(fail_response)    # attempt 2: tests still fail
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(resolve_response)  # resolve attempt 2
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(pass_response)    # attempt 3: tests pass

    Adw::GitHub.stubs(:create_issue_comment)

    results, passed, failed = PBT.run_tests_with_resolution(@adw_id, @issue_number, @logger)

    assert_equal 1, results.length
    assert_equal 1, passed
    assert_equal 0, failed
  end

  def test_run_tests_with_resolution_no_tests_resolved_stops_retrying
    failing_results = [
      { test_name: "t1", passed: false, execution_command: "c", test_purpose: "p", error: "err" }
    ]

    fail_response = build_agent_prompt_response(output: JSON.generate(failing_results), success: true)
    resolve_fail_response = build_agent_prompt_response(success: false, output: "could not fix")

    agent_calls = sequence("agent_calls")
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(fail_response)         # run_tests
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(resolve_fail_response)  # resolve fails

    Adw::GitHub.stubs(:create_issue_comment)

    results, passed, failed = PBT.run_tests_with_resolution(@adw_id, @issue_number, @logger)

    assert_equal 1, results.length
    assert_equal 0, passed
    assert_equal 1, failed
  end

  def test_run_tests_with_resolution_max_attempts_reached
    failing_results = [
      { test_name: "t1", passed: false, execution_command: "c", test_purpose: "p", error: "err" }
    ]

    fail_response = build_agent_prompt_response(output: JSON.generate(failing_results), success: true)
    resolve_response = build_agent_prompt_response(success: true)

    agent_calls = sequence("agent_calls")
    # 4 attempts: each attempt = run_tests + resolve (except last has no resolve)
    # Attempt 1: run_tests (fail) + resolve (success)
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(fail_response)
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(resolve_response)
    # Attempt 2: run_tests (fail) + resolve (success)
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(fail_response)
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(resolve_response)
    # Attempt 3: run_tests (fail) + resolve (success)
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(fail_response)
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(resolve_response)
    # Attempt 4 (last): run_tests (fail) - no resolve since it's the last attempt
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(fail_response)

    Adw::GitHub.stubs(:create_issue_comment)

    results, passed, failed = PBT.run_tests_with_resolution(@adw_id, @issue_number, @logger)

    assert_equal 1, results.length
    assert_equal 0, passed
    assert_equal 1, failed
  end

  def test_run_tests_with_resolution_agent_error_breaks_loop
    error_response = build_agent_prompt_response(output: "agent crash", success: false)

    Adw::Agent.expects(:execute_template).once.returns(error_response)
    Adw::GitHub.stubs(:create_issue_comment)

    results, passed, failed = PBT.run_tests_with_resolution(@adw_id, @issue_number, @logger)

    assert_equal [], results
    assert_equal 0, passed
    assert_equal 0, failed
  end

  # ──────────────────────────────────────────────
  # format_test_results_comment
  # ──────────────────────────────────────────────

  def test_format_test_results_comment_empty_results
    result = PBT.format_test_results_comment([], 0, 0)
    assert_equal "No se encontraron resultados de tests", result
  end

  def test_format_test_results_comment_mixed_results
    results = [
      build_failing_test("test_broken", error: "assertion error"),
      build_passing_test("test_ok")
    ]

    comment = PBT.format_test_results_comment(results, 1, 1)

    assert_includes comment, "## Tests Fallidos"
    assert_includes comment, "### test_broken"
    assert_includes comment, "## Tests Superados"
    assert_includes comment, "### test_ok"
    assert_includes comment, "```json"
  end

  def test_format_test_results_comment_only_passed
    results = [build_passing_test("test_ok")]

    comment = PBT.format_test_results_comment(results, 1, 0)

    refute_includes comment, "## Tests Fallidos"
    assert_includes comment, "## Tests Superados"
    assert_includes comment, "### test_ok"
  end

  def test_format_test_results_comment_only_failed
    results = [build_failing_test("test_broken")]

    comment = PBT.format_test_results_comment(results, 0, 1)

    assert_includes comment, "## Tests Fallidos"
    refute_includes comment, "## Tests Superados"
    assert_includes comment, "### test_broken"
  end

  # ──────────────────────────────────────────────
  # log_test_results
  # ──────────────────────────────────────────────

  def test_log_test_results_summary_format
    results = [
      build_passing_test("test_one"),
      build_failing_test("test_two", error: "something broke")
    ]

    comment_body = nil
    Adw::GitHub.expects(:create_issue_comment).with do |issue_num, body|
      comment_body = body
      issue_num == @issue_number
    end

    PBT.log_test_results(@issue_number, @adw_id, results, @logger)

    assert_includes comment_body, "**Total:** 2"
    assert_includes comment_body, "**Pasados:** 1"
    assert_includes comment_body, "**Fallidos:** 1"
    assert_includes comment_body, "PASS **test_one**"
    assert_includes comment_body, "FAIL **test_two**"
    assert_includes comment_body, "Estado General: FALLIDO"
  end

  def test_log_test_results_all_passing
    results = [build_passing_test("test_ok")]

    comment_body = nil
    Adw::GitHub.expects(:create_issue_comment).with do |_issue, body|
      comment_body = body
      true
    end

    PBT.log_test_results(@issue_number, @adw_id, results, @logger)

    assert_includes comment_body, "Estado General: PASADO"
    assert_includes comment_body, "**Total:** 1"
    assert_includes comment_body, "**Pasados:** 1"
    assert_includes comment_body, "**Fallidos:** 0"
  end

  def test_log_test_results_creates_github_comment
    results = [build_passing_test]

    Adw::GitHub.expects(:create_issue_comment).with(@issue_number, anything).once

    PBT.log_test_results(@issue_number, @adw_id, results, @logger)
  end

  # ──────────────────────────────────────────────
  # main flow
  # ──────────────────────────────────────────────

  def test_main_happy_path_tests_pass_no_changes
    stub_main_args("42", "abc12345")
    stub_logger
    stub_plan_build_success
    stub_tracker_load({})

    # Tests pass on first try
    passing_results = [
      { test_name: "t1", passed: true, execution_command: "c", test_purpose: "p" }
    ]
    pass_response = build_agent_prompt_response(output: JSON.generate(passing_results), success: true)
    Adw::Agent.stubs(:execute_template).returns(pass_response)

    # No changes pending
    no_changes_status = build_mock_status(success: true)
    Open3.stubs(:capture3).with("git", "status", "--porcelain").returns(["", "", no_changes_status])

    Adw::GitHub.stubs(:create_issue_comment)
    Adw::Tracker.stubs(:update)

    PBT.main
  end

  def test_main_plan_build_fails_exits_1
    stub_main_args("42", "abc12345")
    stub_logger
    stub_plan_build_failure(exitstatus: 2)

    assert_raises(SystemExit) do
      PBT.main
    end
  end

  def test_main_tests_fail_and_unresolvable_exits_1
    stub_main_args("42", "abc12345")
    stub_logger
    stub_plan_build_success
    stub_tracker_load({})

    failing_results = [
      { test_name: "t1", passed: false, execution_command: "c", test_purpose: "p", error: "err" }
    ]
    fail_test_response = build_agent_prompt_response(output: JSON.generate(failing_results), success: true)
    resolve_fail_response = build_agent_prompt_response(success: false, output: "nope")

    agent_calls = sequence("agent_calls")
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(fail_test_response)   # run_tests
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(resolve_fail_response) # resolve fails

    Adw::GitHub.stubs(:create_issue_comment)
    Adw::Tracker.stubs(:update)

    assert_raises(SystemExit) do
      PBT.main
    end
  end

  def test_main_tests_fail_then_resolved_commits_and_pushes
    stub_main_args("42", "abc12345")
    stub_logger
    stub_plan_build_success
    stub_tracker_load({})

    failing_results = [
      { test_name: "t1", passed: false, execution_command: "c", test_purpose: "p", error: "err" }
    ]
    passing_results = [
      { test_name: "t1", passed: true, execution_command: "c", test_purpose: "p" }
    ]

    fail_test_response = build_agent_prompt_response(output: JSON.generate(failing_results), success: true)
    pass_test_response = build_agent_prompt_response(output: JSON.generate(passing_results), success: true)
    resolve_response = build_agent_prompt_response(success: true)
    commit_response = build_agent_prompt_response(success: true)

    agent_calls = sequence("agent_calls")
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(fail_test_response)  # run_tests (fail)
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(resolve_response)    # resolve
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(pass_test_response)  # run_tests (pass)
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(commit_response)     # commit

    # Has changes
    changes_status = build_mock_status(success: true)
    push_status = build_mock_status(success: true)
    Open3.expects(:capture3).with("git", "status", "--porcelain").returns(["M file.rb\n", "", changes_status])
    Open3.expects(:capture3).with("git", "push").returns(["", "", push_status])

    Adw::GitHub.stubs(:create_issue_comment)
    Adw::Tracker.stubs(:update)

    PBT.main
  end

  def test_main_tests_pass_with_changes_commits_and_pushes
    stub_main_args("42", "abc12345")
    stub_logger
    stub_plan_build_success
    stub_tracker_load({})

    passing_results = [
      { test_name: "t1", passed: true, execution_command: "c", test_purpose: "p" }
    ]
    pass_response = build_agent_prompt_response(output: JSON.generate(passing_results), success: true)
    commit_response = build_agent_prompt_response(success: true)

    agent_calls = sequence("agent_calls")
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(pass_response)    # run_tests
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(commit_response)  # commit

    changes_status = build_mock_status(success: true)
    push_status = build_mock_status(success: true)
    Open3.expects(:capture3).with("git", "status", "--porcelain").returns(["M file.rb\n", "", changes_status])
    Open3.expects(:capture3).with("git", "push").returns(["", "", push_status])

    Adw::GitHub.stubs(:create_issue_comment)
    Adw::Tracker.stubs(:update)

    PBT.main
  end

  def test_main_tests_pass_no_changes_skips_commit
    stub_main_args("42", "abc12345")
    stub_logger
    stub_plan_build_success
    stub_tracker_load({})

    passing_results = [
      { test_name: "t1", passed: true, execution_command: "c", test_purpose: "p" }
    ]
    pass_response = build_agent_prompt_response(output: JSON.generate(passing_results), success: true)

    # Only one execute_template call for run_tests; no commit call
    Adw::Agent.expects(:execute_template).once.returns(pass_response)

    no_changes_status = build_mock_status(success: true)
    Open3.expects(:capture3).with("git", "status", "--porcelain").returns(["", "", no_changes_status])
    Open3.expects(:capture3).with("git", "push").never

    Adw::GitHub.stubs(:create_issue_comment)
    Adw::Tracker.stubs(:update)

    PBT.main
  end

  def test_main_tracker_set_to_error_on_test_failure
    stub_main_args("42", "abc12345")
    stub_logger
    stub_plan_build_success
    stub_tracker_load({})

    failing_results = [
      { test_name: "t1", passed: false, execution_command: "c", test_purpose: "p", error: "err" }
    ]
    fail_response = build_agent_prompt_response(output: JSON.generate(failing_results), success: true)
    resolve_fail_response = build_agent_prompt_response(success: false, output: "nope")

    agent_calls = sequence("agent_calls")
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(fail_response)
    Adw::Agent.expects(:execute_template).in_sequence(agent_calls).returns(resolve_fail_response)

    Adw::GitHub.stubs(:create_issue_comment)
    Adw::Tracker.expects(:update).with(anything, anything, "testing", anything)
    Adw::Tracker.expects(:update).with(anything, anything, "error", anything)

    assert_raises(SystemExit) do
      PBT.main
    end
  end

  def test_main_tracker_set_to_done_on_success
    stub_main_args("42", "abc12345")
    stub_logger
    stub_plan_build_success
    stub_tracker_load({})

    passing_results = [
      { test_name: "t1", passed: true, execution_command: "c", test_purpose: "p" }
    ]
    pass_response = build_agent_prompt_response(output: JSON.generate(passing_results), success: true)
    Adw::Agent.stubs(:execute_template).returns(pass_response)

    no_changes_status = build_mock_status(success: true)
    Open3.stubs(:capture3).with("git", "status", "--porcelain").returns(["", "", no_changes_status])

    Adw::GitHub.stubs(:create_issue_comment)
    Adw::Tracker.expects(:update).with(anything, anything, "testing", anything)
    Adw::Tracker.expects(:update).with(anything, anything, "done", anything)

    PBT.main
  end

  private

  def stub_main_args(*args)
    ARGV.replace(args)
  end

  def stub_logger
    Adw::Utils.stubs(:setup_logger).returns(@logger)
    Adw::Utils.stubs(:make_adw_id).returns("abc12345")
  end

  def stub_plan_build_success
    Process.stubs(:spawn).returns(12345)
    mock_status = build_mock_status(success: true, exitstatus: 0)
    Process.stubs(:wait2).with(12345).returns([12345, mock_status])
  end

  def stub_plan_build_failure(exitstatus: 1)
    Process.stubs(:spawn).returns(12345)
    mock_status = build_mock_status(success: false, exitstatus: exitstatus)
    Process.stubs(:wait2).with(12345).returns([12345, mock_status])
  end

  def stub_tracker_load(tracker_data)
    Adw::Tracker.stubs(:load).returns(tracker_data)
  end
end
