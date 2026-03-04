# frozen_string_literal: true
module Adw
  module Actors
    class ImplementPlan < Actor
      include Adw::Actors::PipelineInputs
      input :plan_path
      input :tracker
      output :tracker

      def call
        log_actor("Implementing plan (agent: sdlc_implementor)")
        Adw::Tracker.update(tracker, issue_number, "implementing", logger)

        request = Adw::AgentTemplateRequest.new(
          agent_name: "sdlc_implementor",
          slash_command: "/implement",
          args: [plan_path],
          issue_number: issue_number,
          adw_id: adw_id,
          model: "sonnet"
        )

        response = Adw::Agent.execute_template(request)

        unless response.success
          Adw::Tracker.update(tracker, issue_number, "error", logger)
          fail!(error: "Implementation failed: #{response.output}")
        end

        logger.info("Plan implemented successfully")
      end
    end
  end
end
