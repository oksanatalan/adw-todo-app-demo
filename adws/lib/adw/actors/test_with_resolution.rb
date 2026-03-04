# frozen_string_literal: true

module Adw
  module Actors
    class TestWithResolution < Actor
      include Adw::Actors::PipelineInputs

      input :tracker
      input :test_agent_name,  default: -> { "test_runner" }
      input :resolver_prefix,  default: -> { "test_resolver" }
      input :ops_agent_name,   default: -> { "ops" }
      input :verbose_comments, default: -> { false }

      output :tracker
      output :test_results   # Array<Adw::TestResult>
      output :passed_count   # Integer
      output :failed_count   # Integer

      MAX_ATTEMPTS = Adw::PipelineHelpers::MAX_TEST_RETRY_ATTEMPTS

      def call
        log_actor("Running tests (agent: #{test_agent_name})")
        Adw::Tracker.update(tracker, issue_number, "testing", logger)
        attempt = 0
        results = []
        passed = 0
        failed = 0

        while attempt < MAX_ATTEMPTS
          attempt += 1
          logger.info("Test run - attempt #{attempt}/#{MAX_ATTEMPTS}")

          log_dir = File.join(Adw.project_root, ".issues", issue_number.to_s,
                              "logs", adw_id, test_agent_name)
          request = Adw::AgentTemplateRequest.new(
            agent_name: test_agent_name,
            slash_command: "/adw:test",
            args: [log_dir],
            issue_number: issue_number,
            adw_id: adw_id,
            model: "sonnet",
            cwd: worktree_path
          )

          test_response = Adw::Agent.execute_template(request)

          unless test_response.success
            logger.error("Error running tests: #{test_response.output}")
            post_comment("Error running tests: #{test_response.output}") if verbose_comments
            break
          end

          results, passed, failed = Adw::PipelineHelpers.parse_test_results(test_response.output, logger)

          break if failed == 0
          break if attempt == MAX_ATTEMPTS

          post_comment("Found #{failed} failed tests. Attempting resolution...") if verbose_comments
          logger.info("Attempting to resolve #{failed} failed tests")

          failed_tests = results.reject(&:passed)
          resolved = resolve_failed_tests(failed_tests, attempt)

          break if resolved == 0

          logger.info("Re-running tests after resolving #{resolved} tests")
        end

        if attempt == MAX_ATTEMPTS && failed > 0
          logger.warn("Max retries (#{MAX_ATTEMPTS}) reached with #{failed} failures")
          post_comment("Max retries (#{MAX_ATTEMPTS}) reached with #{failed} failures") if verbose_comments
        end

        self.tracker = tracker
        self.test_results = results
        self.passed_count = passed
        self.failed_count = failed
      end

      private

      def resolve_failed_tests(failed_tests, iteration)
        resolved = 0
        failed_tests.each_with_index do |test, idx|
          agent_name = "#{resolver_prefix}_iter#{iteration}_#{idx}"
          test_payload = JSON.generate(test.to_h)

          resolve_request = Adw::AgentTemplateRequest.new(
            agent_name: agent_name,
            slash_command: "/adw:resolve_failed_test",
            args: [test_payload],
            issue_number: issue_number,
            adw_id: adw_id,
            model: "sonnet",
            cwd: worktree_path
          )

          if verbose_comments
            post_comment("Attempting to resolve: #{test.test_name}")
          end

          response = Adw::Agent.execute_template(resolve_request)
          resolved += 1 if response.success
        end
        resolved
      end

      def post_comment(message)
        Adw::GitHub.create_issue_comment(
          issue_number,
          Adw::PipelineHelpers.format_issue_message(adw_id, ops_agent_name, message)
        )
      end
    end
  end
end
