# frozen_string_literal: true

require_relative "test_helper"

class SmokeTest < Minitest::Test
  include TestHelpers

  def test_adw_module_loaded
    assert defined?(Adw)
  end

  def test_build_github_issue
    issue = build_github_issue
    assert_instance_of Adw::GitHubIssue, issue
  end

  def test_build_agent_response
    response = build_agent_response(output: "hello", success: true)
    assert response.success
    assert_equal "hello", response.output
  end

  def test_mock_logger
    logger = mock_logger
    logger.info("test") # should not raise
  end
end
