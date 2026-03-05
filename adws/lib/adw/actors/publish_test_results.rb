# frozen_string_literal: true

module Adw
  module Actors
    class PublishTestResults < Actor
      include Adw::Actors::PipelineInputs

      input :test_results   # Array<Adw::TestResult>
      input :passed_count
      input :failed_count
      input :tracker
      output :tracker

      def call
        log_actor("Publishing test results")
        parts = []
        if failed_count > 0
          parts << "❌ **#{passed_count} passed** | **#{failed_count} failed**"
        else
          parts << "✅ **#{passed_count} passed**"
        end
        parts << ""

        test_results.each do |result|
          emoji = result.passed ? "✅" : "❌"
          line = "- #{emoji} #{result.test_name}"
          line += " — `#{result.error[0..100]}`" if !result.passed && result.error
          parts << line
        end

        comment_id = Adw::GitHub.create_issue_comment(
          issue_number,
          Adw::PipelineHelpers.format_issue_message(adw_id, prefixed_name("test_summary"), parts.join("\n"))
        )
        Adw::Tracker.set_phase_comment(tracker, "test", comment_id)
        Adw::Tracker.save(issue_number, tracker)
        logger.info("Test results posted to issue ##{issue_number}")

        if failed_count > 0
          Adw::Tracker.update(tracker, issue_number, "error", logger)
          fail!(error: "#{failed_count} tests failed after all retry attempts")
        end
      end
    end
  end
end
