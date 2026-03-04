# frozen_string_literal: true

module Adw
  module Actors
    class ReviewIssue < Actor
      include Adw::Actors::PipelineInputs

      input :issue
      input :tracker
      output :tracker

      def call
        log_actor("Reviewing issue visually (agent: issue_reviewer)")
        Adw::Tracker.update(tracker, issue_number, "reviewing_issue", logger)
        plan_path = Adw::PipelineHelpers.plan_path_for(issue_number)

        request = Adw::AgentTemplateRequest.new(
          agent_name: "issue_reviewer",
          slash_command: "/adw:review:issue",
          args: [issue.to_json, plan_path],
          issue_number: issue_number,
          adw_id: adw_id,
          model: "sonnet"
        )

        logger.info("Running issue review...")
        response = Adw::Agent.execute_template(request)

        unless response.success
          logger.warn("Issue review failed (non-blocking): #{response.output}")
          Adw::GitHub.create_issue_comment(
            issue_number,
            Adw::PipelineHelpers.format_issue_message(adw_id, "issue_reviewer",
              "Warning: Could not complete visual review: #{response.output}")
          )
          return
        end

        result = Adw::PipelineHelpers.parse_issue_review_results(response.output, logger)

        if result[:success] && result[:screenshots]&.any?
          begin
            result[:screenshots] = Adw::R2.upload_evidence(adw_id, result[:screenshots], logger)
            Adw::PipelineHelpers.link_screenshot_urls(result[:screenshots], result[:review_issues])
          rescue Aws::S3::Errors::ServiceError, Errno::ENOENT => e
            logger.warn("R2 upload failed (non-blocking): #{e.message}")
            result[:errors] ||= []
            result[:errors] << "R2 upload failed: #{e.message}"
          end
        end

        evidence_comment = Adw::PipelineHelpers.format_evidence_comment(result)
        comment_id = Adw::GitHub.create_issue_comment(
          issue_number,
          Adw::PipelineHelpers.format_issue_message(adw_id, "issue_reviewer", evidence_comment)
        )
        Adw::Tracker.set_phase_comment(tracker, "review_issue", comment_id)
        Adw::Tracker.save(issue_number, tracker)
        logger.info("Visual evidence published to issue ##{issue_number}")
      rescue => e
        logger.warn("ReviewIssue actor failed (non-blocking): #{e.message}")
      end
    end
  end
end
