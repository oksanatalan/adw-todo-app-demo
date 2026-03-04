# frozen_string_literal: true

require_relative "../test_helper"
load File.expand_path("../../bin/trigger_cron", __dir__)

class TriggerCronTest < Minitest::Test
  include TestFactories

  def setup
    @cron = Adw::Pipelines::TriggerCron.new("owner/repo")
  end

  # ---------------------------------------------------------------------------
  # should_process_issue?
  # ---------------------------------------------------------------------------

  def test_should_process_issue_no_comments_returns_true
    Adw::GitHub.stubs(:fetch_issue_comments).with("owner/repo", 1).returns([])

    assert @cron.should_process_issue?(1)
  end

  def test_should_process_issue_latest_comment_adw_lowercase_returns_true
    comments = [build_comment(id: "c1", body: "adw")]
    Adw::GitHub.stubs(:fetch_issue_comments).with("owner/repo", 1).returns(comments)

    assert @cron.should_process_issue?(1)
  end

  def test_should_process_issue_latest_comment_adw_uppercase_returns_true
    comments = [build_comment(id: "c1", body: "ADW")]
    Adw::GitHub.stubs(:fetch_issue_comments).with("owner/repo", 1).returns(comments)

    assert @cron.should_process_issue?(1)
  end

  def test_should_process_issue_latest_comment_other_text_returns_false
    comments = [build_comment(id: "c1", body: "some other comment")]
    Adw::GitHub.stubs(:fetch_issue_comments).with("owner/repo", 1).returns(comments)

    refute @cron.should_process_issue?(1)
  end

  def test_should_process_issue_already_processed_comment_returns_false
    @cron.issue_last_comment[1] = "c1"
    comments = [build_comment(id: "c1", body: "adw")]
    Adw::GitHub.stubs(:fetch_issue_comments).with("owner/repo", 1).returns(comments)

    refute @cron.should_process_issue?(1)
  end

  def test_should_process_issue_new_comment_after_processed_returns_true
    @cron.issue_last_comment[1] = "c1"
    comments = [
      build_comment(id: "c1", body: "adw"),
      build_comment(id: "c2", body: "adw", created_at: "2024-01-02T00:00:00Z")
    ]
    Adw::GitHub.stubs(:fetch_issue_comments).with("owner/repo", 1).returns(comments)

    assert @cron.should_process_issue?(1)
  end

  def test_should_process_issue_records_comment_id_on_adw_match
    comments = [build_comment(id: "c42", body: "adw")]
    Adw::GitHub.stubs(:fetch_issue_comments).with("owner/repo", 5).returns(comments)

    @cron.should_process_issue?(5)

    assert_equal "c42", @cron.issue_last_comment[5]
  end

  # ---------------------------------------------------------------------------
  # check_patch_trigger
  # ---------------------------------------------------------------------------

  def test_check_patch_trigger_new_human_comment_returns_body
    comments = [build_comment(id: "c1", body: "Please fix the button color")]
    Adw::GitHub.stubs(:fetch_issue_comments).with("owner/repo", 1).returns(comments)

    result = @cron.check_patch_trigger(1)
    assert_equal "Please fix the button color", result
  end

  def test_check_patch_trigger_bot_comment_returns_nil
    bot_body = "a1b2c3d4_ops: some bot message"
    comments = [build_comment(id: "c1", body: bot_body)]
    Adw::GitHub.stubs(:fetch_issue_comments).with("owner/repo", 1).returns(comments)

    assert_nil @cron.check_patch_trigger(1)
  end

  def test_check_patch_trigger_tracker_comment_returns_nil
    tracker_body = "Some text\n#{Adw::Tracker::COMMENT_MARKER}"
    comments = [build_comment(id: "c1", body: tracker_body)]
    Adw::GitHub.stubs(:fetch_issue_comments).with("owner/repo", 1).returns(comments)

    assert_nil @cron.check_patch_trigger(1)
  end

  def test_check_patch_trigger_no_comments_returns_nil
    Adw::GitHub.stubs(:fetch_issue_comments).with("owner/repo", 1).returns([])

    assert_nil @cron.check_patch_trigger(1)
  end

  def test_check_patch_trigger_already_processed_comment_returns_nil
    @cron.issue_last_comment[1] = "c1"
    comments = [build_comment(id: "c1", body: "Fix this please")]
    Adw::GitHub.stubs(:fetch_issue_comments).with("owner/repo", 1).returns(comments)

    assert_nil @cron.check_patch_trigger(1)
  end

  def test_check_patch_trigger_new_comment_after_processed_returns_body
    @cron.issue_last_comment[1] = "c1"
    comments = [
      build_comment(id: "c1", body: "old comment"),
      build_comment(id: "c2", body: "new feedback", created_at: "2024-01-02T00:00:00Z")
    ]
    Adw::GitHub.stubs(:fetch_issue_comments).with("owner/repo", 1).returns(comments)

    result = @cron.check_patch_trigger(1)
    assert_equal "new feedback", result
  end

  def test_check_patch_trigger_records_comment_id
    comments = [build_comment(id: "c99", body: "Fix the layout")]
    Adw::GitHub.stubs(:fetch_issue_comments).with("owner/repo", 3).returns(comments)

    @cron.check_patch_trigger(3)

    assert_equal "c99", @cron.issue_last_comment[3]
  end

  # ---------------------------------------------------------------------------
  # trigger_workflow
  # ---------------------------------------------------------------------------

  def test_trigger_workflow_success_spawns_process
    Process.stubs(:spawn).returns(12345)
    Process.stubs(:detach).with(12345).returns(nil)

    result = @cron.trigger_workflow(7)

    assert result
  end

  def test_trigger_workflow_passes_issue_number_as_string
    captured = nil
    Process.stubs(:spawn).with { |*args, **kwargs| captured = { args: args, kwargs: kwargs }; true }.returns(12345)
    Process.stubs(:detach).returns(nil)

    @cron.trigger_workflow(7)

    assert_equal RbConfig.ruby, captured[:args][0]
    assert captured[:args][1].end_with?("adw_full_pipeline"), "Expected script path to end with adw_full_pipeline"
    assert_equal "7", captured[:args][2]
  end

  def test_trigger_workflow_exception_returns_false
    Process.stubs(:spawn).raises(Errno::ENOENT, "No such file")

    result = @cron.trigger_workflow(7)

    refute result
  end

  # ---------------------------------------------------------------------------
  # trigger_patch_workflow
  # ---------------------------------------------------------------------------

  def test_trigger_patch_workflow_success_returns_true
    Process.stubs(:spawn).returns(54321)
    Process.stubs(:detach).with(54321).returns(nil)

    result = @cron.trigger_patch_workflow(3, "Fix the header")

    assert result
  end

  def test_trigger_patch_workflow_passes_issue_number_and_comment_body
    captured = nil
    Process.stubs(:spawn).with { |*args, **kwargs| captured = { args: args, kwargs: kwargs }; true }.returns(54321)
    Process.stubs(:detach).returns(nil)

    @cron.trigger_patch_workflow(3, "Fix the header")

    assert_equal RbConfig.ruby, captured[:args][0]
    assert captured[:args][1].end_with?("adw_patch"), "Expected script path to end with adw_patch"
    assert_equal "3", captured[:args][2]
    assert_equal "Fix the header", captured[:args][3]
  end

  def test_trigger_patch_workflow_exception_returns_false
    Process.stubs(:spawn).raises(RuntimeError, "spawn failed")

    result = @cron.trigger_patch_workflow(3, "Fix the header")

    refute result
  end

  # ---------------------------------------------------------------------------
  # check_and_process_issues — routing logic
  # ---------------------------------------------------------------------------

  def test_check_and_process_issues_shutdown_returns_immediately
    @cron.shutdown_requested = true
    Adw::GitHub.expects(:fetch_open_issues).never

    @cron.check_and_process_issues
  end

  def test_check_and_process_issues_no_open_issues
    Adw::GitHub.stubs(:fetch_open_issues).with("owner/repo").returns([])

    @cron.check_and_process_issues
    # Should not raise; just logs "No open issues found"
  end

  def test_check_and_process_issues_done_label_new_human_comment_triggers_patch
    done_label = build_label(name: "adw/done", color: "0E8A16")
    issue = build_issue_list_item(number: 1, labels: [done_label])
    Adw::GitHub.stubs(:fetch_open_issues).with("owner/repo").returns([issue])

    # check_patch_trigger returns a comment body
    @cron.expects(:check_patch_trigger).with(1).returns("Please fix the button")
    @cron.expects(:trigger_patch_workflow).with(1, "Please fix the button").returns(true)
    # should_process_issue? should NOT be called for done issues
    @cron.expects(:should_process_issue?).never

    @cron.check_and_process_issues
  end

  def test_check_and_process_issues_done_label_bot_comment_skips
    done_label = build_label(name: "adw/done", color: "0E8A16")
    issue = build_issue_list_item(number: 1, labels: [done_label])
    Adw::GitHub.stubs(:fetch_open_issues).with("owner/repo").returns([issue])

    # check_patch_trigger returns nil (bot comment)
    @cron.expects(:check_patch_trigger).with(1).returns(nil)
    @cron.expects(:trigger_patch_workflow).never
    @cron.expects(:trigger_workflow).never

    @cron.check_and_process_issues
  end

  def test_check_and_process_issues_no_adw_labels_no_comments_triggers_full
    issue = build_issue_list_item(number: 2, labels: [])
    Adw::GitHub.stubs(:fetch_open_issues).with("owner/repo").returns([issue])
    @cron.expects(:should_process_issue?).with(2).returns(true)
    @cron.expects(:trigger_workflow).with(2).returns(true)

    @cron.check_and_process_issues

    assert @cron.processed_issues.include?(2)
  end

  def test_check_and_process_issues_implementing_label_skips
    impl_label = build_label(name: "adw/implementing", color: "FEF2C0")
    issue = build_issue_list_item(number: 3, labels: [impl_label])
    Adw::GitHub.stubs(:fetch_open_issues).with("owner/repo").returns([issue])
    @cron.expects(:should_process_issue?).never
    @cron.expects(:trigger_workflow).never

    @cron.check_and_process_issues
  end

  def test_check_and_process_issues_error_label_qualifies_triggers_full
    error_label = build_label(name: "adw/error", color: "E11D48")
    issue = build_issue_list_item(number: 4, labels: [error_label])
    Adw::GitHub.stubs(:fetch_open_issues).with("owner/repo").returns([issue])
    @cron.expects(:should_process_issue?).with(4).returns(true)
    @cron.expects(:trigger_workflow).with(4).returns(true)

    @cron.check_and_process_issues

    assert @cron.processed_issues.include?(4)
  end

  def test_check_and_process_issues_already_processed_skips_full_pipeline
    @cron.processed_issues.add(6)
    issue = build_issue_list_item(number: 6, labels: [])
    Adw::GitHub.stubs(:fetch_open_issues).with("owner/repo").returns([issue])
    @cron.expects(:should_process_issue?).never
    @cron.expects(:trigger_workflow).never

    @cron.check_and_process_issues
  end

  def test_check_and_process_issues_done_already_processed_still_checks_patch
    @cron.processed_issues.add(7)
    done_label = build_label(name: "adw/done", color: "0E8A16")
    issue = build_issue_list_item(number: 7, labels: [done_label])
    Adw::GitHub.stubs(:fetch_open_issues).with("owner/repo").returns([issue])

    # Even though issue 7 was previously processed (full pipeline), patch check should still run
    @cron.expects(:check_patch_trigger).with(7).returns("New feedback")
    @cron.expects(:trigger_patch_workflow).with(7, "New feedback").returns(true)

    @cron.check_and_process_issues
  end

  def test_check_and_process_issues_multiple_issues_both_types
    done_label = build_label(name: "adw/done", color: "0E8A16")
    done_issue = build_issue_list_item(number: 10, labels: [done_label])
    new_issue = build_issue_list_item(number: 11, labels: [])

    Adw::GitHub.stubs(:fetch_open_issues).with("owner/repo").returns([done_issue, new_issue])

    @cron.expects(:check_patch_trigger).with(10).returns("Patch this")
    @cron.expects(:trigger_patch_workflow).with(10, "Patch this").returns(true)
    @cron.expects(:should_process_issue?).with(11).returns(true)
    @cron.expects(:trigger_workflow).with(11).returns(true)

    @cron.check_and_process_issues

    assert @cron.processed_issues.include?(11)
  end

  def test_check_and_process_issues_adds_to_processed_on_success
    issue = build_issue_list_item(number: 20, labels: [])
    Adw::GitHub.stubs(:fetch_open_issues).with("owner/repo").returns([issue])
    @cron.expects(:should_process_issue?).with(20).returns(true)
    @cron.expects(:trigger_workflow).with(20).returns(true)

    refute @cron.processed_issues.include?(20)
    @cron.check_and_process_issues
    assert @cron.processed_issues.include?(20)
  end

  def test_check_and_process_issues_does_not_add_to_processed_on_failure
    issue = build_issue_list_item(number: 21, labels: [])
    Adw::GitHub.stubs(:fetch_open_issues).with("owner/repo").returns([issue])
    @cron.expects(:should_process_issue?).with(21).returns(true)
    @cron.expects(:trigger_workflow).with(21).returns(false)

    @cron.check_and_process_issues

    refute @cron.processed_issues.include?(21)
  end

  def test_check_and_process_issues_reviewing_label_skips
    reviewing_label = build_label(name: "adw/reviewing", color: "F9A825")
    issue = build_issue_list_item(number: 8, labels: [reviewing_label])
    Adw::GitHub.stubs(:fetch_open_issues).with("owner/repo").returns([issue])
    @cron.expects(:should_process_issue?).never
    @cron.expects(:trigger_workflow).never

    @cron.check_and_process_issues
  end

  def test_check_and_process_issues_error_plus_other_label_skips
    error_label = build_label(name: "adw/error", color: "E11D48")
    impl_label = build_label(name: "adw/implementing", color: "FEF2C0")
    issue = build_issue_list_item(number: 9, labels: [error_label, impl_label])
    Adw::GitHub.stubs(:fetch_open_issues).with("owner/repo").returns([issue])
    # Has adw/implementing (non-error), so it should skip
    @cron.expects(:should_process_issue?).never
    @cron.expects(:trigger_workflow).never

    @cron.check_and_process_issues
  end

  def test_check_and_process_issues_rescue_on_fetch_error
    Adw::GitHub.stubs(:fetch_open_issues).raises(StandardError, "API down")

    # Should not raise — it catches the error internally
    @cron.check_and_process_issues
  end
end
