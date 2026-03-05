# frozen_string_literal: true
module Adw
  module Actors
    class PublishPlan < Actor
      include Adw::Actors::PipelineInputs
      input :plan_path
      input :tracker
      input :title, default: -> { "Implementation Plan" }
      output :tracker

      def call
        agent_name = prefixed_name("sdlc_planner")
        log_actor("Publishing plan to GitHub")
        content = File.read(plan_path)
        body = Adw::PipelineHelpers.format_issue_message(
          adw_id, agent_name,
          "#{title}\n\n<details>\n<summary>#{title}</summary>\n\n#{content}\n</details>"
        )
        comment_id = Adw::GitHub.create_issue_comment(issue_number, body)
        Adw::Tracker.set_phase_comment(tracker, "plan", comment_id)
        Adw::Tracker.save(issue_number, tracker)
        logger.info("#{title} posted to issue ##{issue_number}")
      rescue Errno::ENOENT, StandardError => e
        logger.warn("Could not post plan to issue: #{e.message}")
      end
    end
  end
end
