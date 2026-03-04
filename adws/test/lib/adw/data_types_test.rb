# frozen_string_literal: true

require_relative "../../test_helper"

class GitHubUserTest < Minitest::Test
  include Factories

  def test_construction_from_hash
    user = Adw::GitHubUser.new(github_user_hash)
    assert_equal "octocat", user.login
    assert_equal "Octo Cat", user.name
  end

  def test_transform_keys_converts_string_keys_to_symbols
    user = Adw::GitHubUser.new("login" => "octocat", "name" => "Octo Cat")
    assert_equal "octocat", user.login
    assert_equal "Octo Cat", user.name
  end

  def test_optional_name_defaults_to_nil
    user = Adw::GitHubUser.new(login: "octocat")
    assert_nil user.name
  end
end

class GitHubLabelTest < Minitest::Test
  include Factories

  def test_construction_with_all_fields
    label = Adw::GitHubLabel.new(github_label_hash)
    assert_equal "123", label.id
    assert_equal "bug", label.name
    assert_equal "d73a4a", label.color
    assert_equal "Something is broken", label.description
  end

  def test_id_is_coerced_to_string
    label = Adw::GitHubLabel.new(github_label_hash(id: 456))
    assert_equal "456", label.id
    assert_instance_of String, label.id
  end

  def test_optional_description_defaults_to_nil
    label = Adw::GitHubLabel.new(id: "1", name: "bug", color: "d73a4a")
    assert_nil label.description
  end
end

class GitHubCommentTest < Minitest::Test
  include Factories

  def test_transform_keys_converts_camel_case
    comment = Adw::GitHubComment.new(github_comment_hash)
    assert_equal "2025-01-01T00:00:00Z", comment.created_at
  end

  def test_all_fields_present
    comment = Adw::GitHubComment.new(github_comment_hash)
    assert_equal "100", comment.id
    assert_equal "This is a comment", comment.body
    assert_instance_of Adw::GitHubUser, comment.author
    assert_equal "octocat", comment.author.login
  end
end

class GitHubIssueListItemTest < Minitest::Test
  include Factories

  def test_construction_from_api_like_hash
    item = Adw::GitHubIssueListItem.new(github_issue_list_item_hash)
    assert_equal 1, item.number
    assert_equal "Test issue", item.title
    assert_equal "Test body", item.body
    assert_equal "2025-01-01T00:00:00Z", item.created_at
    assert_equal "2025-01-02T00:00:00Z", item.updated_at
  end

  def test_labels_defaults_to_empty_array
    item = Adw::GitHubIssueListItem.new(
      number: 1, title: "T", body: "B",
      createdAt: "2025-01-01T00:00:00Z", updatedAt: "2025-01-02T00:00:00Z"
    )
    assert_equal [], item.labels
  end

  def test_number_is_integer
    item = Adw::GitHubIssueListItem.new(github_issue_list_item_hash)
    assert_instance_of Integer, item.number
  end
end

class GitHubIssueTest < Minitest::Test
  include Factories

  def test_full_construction_from_api_like_hash
    issue = Adw::GitHubIssue.new(github_issue_hash)
    assert_equal 42, issue.number
    assert_equal "Fix login bug", issue.title
    assert_equal "Login is broken", issue.body
    assert_equal "OPEN", issue.state
    assert_equal "https://github.com/owner/repo/issues/42", issue.url
  end

  def test_nested_author
    issue = Adw::GitHubIssue.new(github_issue_hash)
    assert_instance_of Adw::GitHubUser, issue.author
    assert_equal "octocat", issue.author.login
  end

  def test_nested_labels
    issue = Adw::GitHubIssue.new(github_issue_hash)
    assert_instance_of Array, issue.labels
    assert_equal 1, issue.labels.length
    assert_instance_of Adw::GitHubLabel, issue.labels.first
    assert_equal "bug", issue.labels.first.name
  end

  def test_nested_comments
    issue = Adw::GitHubIssue.new(github_issue_hash)
    assert_instance_of Array, issue.comments
    assert_equal 1, issue.comments.length
    assert_instance_of Adw::GitHubComment, issue.comments.first
    assert_equal "This is a comment", issue.comments.first.body
  end

  def test_optional_fields_default_to_nil
    issue = Adw::GitHubIssue.new(github_issue_hash)
    assert_nil issue.milestone
    assert_nil issue.closed_at
  end

  def test_to_json_produces_correct_json_with_camel_case_keys
    issue = Adw::GitHubIssue.new(github_issue_hash)
    json = issue.to_json
    parsed = JSON.parse(json)

    assert_equal 42, parsed["number"]
    assert_equal "Fix login bug", parsed["title"]
    assert_equal "OPEN", parsed["state"]
    # Verify camelCase keys
    assert parsed.key?("createdAt"), "Expected camelCase key 'createdAt'"
    assert parsed.key?("updatedAt"), "Expected camelCase key 'updatedAt'"
    assert parsed.key?("closedAt"), "Expected camelCase key 'closedAt'"
    # Verify nested comment uses camelCase
    assert parsed["comments"].first.key?("createdAt"), "Expected camelCase key in comments"
  end

  def test_transform_keys_handles_camel_case
    hash = {
      "number" => 10,
      "title" => "Test",
      "body" => "Body",
      "state" => "OPEN",
      "author" => { "login" => "user", "name" => "User" },
      "assignees" => [],
      "labels" => [],
      "milestone" => nil,
      "comments" => [],
      "createdAt" => "2025-01-01T00:00:00Z",
      "updatedAt" => "2025-01-02T00:00:00Z",
      "closedAt" => nil,
      "url" => "https://github.com/o/r/issues/10"
    }
    issue = Adw::GitHubIssue.new(hash)
    assert_equal "2025-01-01T00:00:00Z", issue.created_at
    assert_equal "2025-01-02T00:00:00Z", issue.updated_at
  end
end

class AgentPromptRequestTest < Minitest::Test
  include Factories

  def test_construction_with_required_fields
    req = Adw::AgentPromptRequest.new(agent_prompt_request_hash)
    assert_equal "Do something", req.prompt
    assert_equal 1, req.issue_number
    assert_equal "abc12345", req.adw_id
    assert_equal "/tmp/output.jsonl", req.output_file
  end

  def test_issue_number_coerces_string_to_integer
    req = Adw::AgentPromptRequest.new(agent_prompt_request_hash(issue_number: "123"))
    assert_equal 123, req.issue_number
    assert_instance_of Integer, req.issue_number
  end

  def test_defaults
    req = Adw::AgentPromptRequest.new(
      prompt: "Test", issue_number: 1, adw_id: "x", output_file: "/tmp/out.jsonl"
    )
    assert_equal "ops", req.agent_name
    assert_equal "sonnet", req.model
    assert_equal false, req.dangerously_skip_permissions
  end
end

class AgentPromptResponseTest < Minitest::Test
  include Factories

  def test_success_true
    resp = Adw::AgentPromptResponse.new(agent_prompt_response_hash(success: true))
    assert resp.success
  end

  def test_success_false
    resp = Adw::AgentPromptResponse.new(agent_prompt_response_hash(success: false))
    refute resp.success
  end

  def test_session_id_optional_defaults_to_nil
    resp = Adw::AgentPromptResponse.new(output: "ok", success: true)
    assert_nil resp.session_id
  end

  def test_session_id_when_provided
    resp = Adw::AgentPromptResponse.new(output: "ok", success: true, session_id: "sess-123")
    assert_equal "sess-123", resp.session_id
  end
end

class AgentTemplateRequestTest < Minitest::Test
  include Factories

  def test_construction_with_required_fields
    req = Adw::AgentTemplateRequest.new(agent_template_request_hash)
    assert_equal "test_runner", req.agent_name
    assert_equal "/adw:test", req.slash_command
    assert_equal 1, req.issue_number
    assert_equal "abc12345", req.adw_id
  end

  def test_args_defaults_to_empty_array
    req = Adw::AgentTemplateRequest.new(
      agent_name: "a", slash_command: "/cmd", issue_number: 1, adw_id: "x"
    )
    assert_equal [], req.args
  end

  def test_model_defaults_to_sonnet
    req = Adw::AgentTemplateRequest.new(
      agent_name: "a", slash_command: "/cmd", issue_number: 1, adw_id: "x"
    )
    assert_equal "sonnet", req.model
  end
end

class TestResultTest < Minitest::Test
  include Factories

  def test_construction_with_all_fields
    result = Adw::TestResult.new(test_result_hash)
    assert_equal "test_login", result.test_name
    assert result.passed
    assert_equal "rails test test/models/user_test.rb", result.execution_command
    assert_equal "Verify user login", result.test_purpose
    assert_nil result.error
  end

  def test_error_is_optional_defaults_to_nil
    result = Adw::TestResult.new(test_result_hash)
    assert_nil result.error
  end

  def test_error_when_provided
    result = Adw::TestResult.new(test_result_hash(error: "assertion failed"))
    assert_equal "assertion failed", result.error
  end

  def test_passed_is_boolean
    passed_result = Adw::TestResult.new(test_result_hash(passed: true))
    assert_equal true, passed_result.passed

    failed_result = Adw::TestResult.new(test_result_hash(passed: false))
    assert_equal false, failed_result.passed
  end
end
