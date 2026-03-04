# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"
require "mocha/minitest"
require "json"
require "open3"
require "logger"

# Set minimal env vars so dotenv does not fail when .env is absent
ENV["CLOUDFLARE_ACCOUNT_ID"] ||= "test"
ENV["CLOUDFLARE_R2_ACCESS_KEY_ID"] ||= "test"
ENV["CLOUDFLARE_R2_SECRET_ACCESS_KEY"] ||= "test"
ENV["CLOUDFLARE_R2_BUCKET_NAME"] ||= "test"
ENV["CLOUDFLARE_R2_PUBLIC_DOMAIN"] ||= "test.example.com"

# Load the ADW library
require_relative "../lib/adw"

# Allow overriding project_root in tests
module Adw
  def self.project_root=(path)
    @test_project_root = path
  end

  class << self
    alias_method :_original_project_root, :project_root

    def project_root
      @test_project_root || _original_project_root
    end
  end
end

# Stub for Open3 process status
class FakeProcessStatus
  def initialize(success)
    @success = success
  end

  def success?
    @success
  end

  def exitstatus
    @success ? 0 : 1
  end
end

# Helpers used by adw_plan_build and adw_full_pipeline tests
module TestHelpers
  def build_github_issue(overrides = {})
    defaults = {
      number: 42,
      title: "Test issue",
      body: "Test body",
      state: "OPEN",
      author: { login: "testuser", name: "Test User" },
      assignees: [],
      labels: [],
      milestone: nil,
      comments: [],
      created_at: "2025-01-01T00:00:00Z",
      updated_at: "2025-01-01T00:00:00Z",
      closed_at: nil,
      url: "https://github.com/test/repo/issues/42"
    }
    Adw::GitHubIssue.new(defaults.merge(overrides))
  end

  def build_agent_response(overrides = {})
    defaults = { output: "", success: true, session_id: nil }
    Adw::AgentPromptResponse.new(defaults.merge(overrides))
  end

  def build_tracker(overrides = {})
    defaults = {
      comment_id: "123",
      adw_id: "abc12345",
      classification: "/feature",
      branch_name: "feature/test-branch",
      status: "testing",
      patches: [],
      phase_comments: {}
    }
    defaults.merge(overrides)
  end

  def build_test_result(overrides = {})
    defaults = {
      test_name: "test_example",
      passed: true,
      execution_command: "ruby -Itest test/example_test.rb",
      test_purpose: "Tests example functionality",
      error: nil
    }
    Adw::TestResult.new(defaults.merge(overrides))
  end

  def mock_logger
    logger = mock("logger")
    logger.stubs(:info)
    logger.stubs(:debug)
    logger.stubs(:warn)
    logger.stubs(:error)
    logger
  end

  def mock_success_status
    status = mock("status")
    status.stubs(:success?).returns(true)
    status.stubs(:exitstatus).returns(0)
    status
  end

  def mock_failure_status
    status = mock("status")
    status.stubs(:success?).returns(false)
    status.stubs(:exitstatus).returns(1)
    status
  end
end

# Helpers used by adw_plan_build_test and data_types tests
module Factories
  def github_user_hash(overrides = {})
    { login: "octocat", name: "Octo Cat" }.merge(overrides)
  end

  def github_label_hash(overrides = {})
    { id: "123", name: "bug", color: "d73a4a", description: "Something is broken" }.merge(overrides)
  end

  def github_comment_hash(overrides = {})
    {
      id: "100",
      author: github_user_hash,
      body: "This is a comment",
      createdAt: "2025-01-01T00:00:00Z"
    }.merge(overrides)
  end

  def github_issue_list_item_hash(overrides = {})
    {
      number: 1,
      title: "Test issue",
      body: "Test body",
      labels: [],
      createdAt: "2025-01-01T00:00:00Z",
      updatedAt: "2025-01-02T00:00:00Z"
    }.merge(overrides)
  end

  def github_issue_hash(overrides = {})
    {
      number: 42,
      title: "Fix login bug",
      body: "Login is broken",
      state: "OPEN",
      author: github_user_hash,
      assignees: [],
      labels: [github_label_hash],
      milestone: nil,
      comments: [github_comment_hash],
      createdAt: "2025-01-01T00:00:00Z",
      updatedAt: "2025-01-02T00:00:00Z",
      closedAt: nil,
      url: "https://github.com/owner/repo/issues/42"
    }.merge(overrides)
  end

  def agent_prompt_request_hash(overrides = {})
    {
      prompt: "Do something",
      issue_number: 1,
      adw_id: "abc12345",
      agent_name: "ops",
      model: "sonnet",
      dangerously_skip_permissions: false,
      output_file: "/tmp/output.jsonl"
    }.merge(overrides)
  end

  def agent_prompt_response_hash(overrides = {})
    { output: "All done", success: true, session_id: nil }.merge(overrides)
  end

  def agent_template_request_hash(overrides = {})
    {
      agent_name: "test_runner",
      slash_command: "/adw:test",
      args: [],
      issue_number: 1,
      adw_id: "abc12345",
      model: "sonnet"
    }.merge(overrides)
  end

  def test_result_hash(overrides = {})
    {
      test_name: "test_login",
      passed: true,
      execution_command: "rails test test/models/user_test.rb",
      test_purpose: "Verify user login",
      error: nil
    }.merge(overrides)
  end

  def build_agent_prompt_response(overrides = {})
    defaults = { output: "test output", success: true, session_id: nil }
    Adw::AgentPromptResponse.new(defaults.merge(overrides))
  end

  def build_agent_template_request(overrides = {})
    defaults = {
      agent_name: "test_agent",
      slash_command: "/adw:test",
      args: [],
      issue_number: 42,
      adw_id: "abc12345",
      model: "sonnet"
    }
    Adw::AgentTemplateRequest.new(defaults.merge(overrides))
  end

  def build_test_result(overrides = {})
    defaults = {
      test_name: "test_example",
      passed: true,
      execution_command: "ruby -e 'puts 1'",
      test_purpose: "verify example",
      error: nil
    }
    Adw::TestResult.new(defaults.merge(overrides))
  end

  def build_passing_test(name = "test_passing")
    build_test_result(test_name: name, passed: true)
  end

  def build_failing_test(name = "test_failing", error: "assertion failed")
    build_test_result(test_name: name, passed: false, error: error)
  end

  def build_mock_logger
    Logger.new(StringIO.new).tap { |l| l.level = Logger::DEBUG }
  end

  def build_mock_status(success: true, exitstatus: nil)
    status = mock("process_status")
    status.stubs(:success?).returns(success)
    status.stubs(:exitstatus).returns(exitstatus || (success ? 0 : 1))
    status
  end
end

# Helpers used by adw_patch and trigger_cron tests
module TestFactories
  def build_agent_response(output: "ok", success: true, session_id: nil)
    Adw::AgentPromptResponse.new(output: output, success: success, session_id: session_id)
  end

  def build_tracker(
    comment_id: "123456",
    adw_id: "test1234",
    classification: "bug",
    branch_name: "feature/test-123",
    status: "done",
    patches: [],
    phase_comments: {}
  )
    {
      comment_id: comment_id,
      adw_id: adw_id,
      classification: classification,
      branch_name: branch_name,
      status: status,
      patches: patches,
      phase_comments: phase_comments
    }
  end

  def build_patch_tracker(
    comment_id: nil,
    adw_id: "patch123",
    status: nil,
    trigger_comment: "Fix the button color",
    patch_file: nil,
    phase_comments: {}
  )
    {
      comment_id: comment_id,
      adw_id: adw_id,
      status: status,
      trigger_comment: trigger_comment,
      patch_file: patch_file,
      phase_comments: phase_comments
    }
  end

  def build_issue(
    number: 42,
    title: "Test Issue",
    body: "Test body",
    state: "OPEN",
    login: "testuser",
    url: "https://github.com/test/repo/issues/42"
  )
    Adw::GitHubIssue.new(
      number: number,
      title: title,
      body: body,
      state: state,
      author: { login: login, name: "Test User" },
      assignees: [],
      labels: [],
      milestone: nil,
      comments: [],
      createdAt: "2024-01-01T00:00:00Z",
      updatedAt: "2024-01-01T00:00:00Z",
      closedAt: nil,
      url: url
    )
  end

  def build_test_result(test_name: "test_something", passed: true, error: nil)
    Adw::TestResult.new(
      test_name: test_name,
      passed: passed,
      execution_command: "ruby -e 'puts 1'",
      test_purpose: "Tests something",
      error: error
    )
  end

  def build_logger
    Logger.new(StringIO.new).tap { |l| l.level = Logger::DEBUG }
  end

  def build_label(name:, id: "1", color: "EDEDED", description: nil)
    Adw::GitHubLabel.new(
      "id" => id,
      "name" => name,
      "color" => color,
      "description" => description
    )
  end

  def build_issue_list_item(number:, title: "Test issue", body: "Body", labels: [], created_at: "2024-01-01T00:00:00Z", updated_at: "2024-01-01T00:00:00Z")
    label_data = labels.map do |l|
      if l.is_a?(Hash)
        l
      else
        { "id" => l.id, "name" => l.name, "color" => l.color, "description" => l.description }
      end
    end
    Adw::GitHubIssueListItem.new(
      "number" => number,
      "title" => title,
      "body" => body,
      "labels" => label_data,
      "createdAt" => created_at,
      "updatedAt" => updated_at
    )
  end

  def build_comment(id:, body:, author_login: "user", created_at: "2024-01-01T00:00:00Z")
    {
      "id" => id,
      "body" => body,
      "author" => { "login" => author_login, "name" => nil },
      "createdAt" => created_at
    }
  end
end
