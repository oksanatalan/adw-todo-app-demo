# frozen_string_literal: true
module Adw
  module Actors
    class ImplementPlan < Actor
      include Adw::Actors::PipelineInputs
      input :plan_path
      input :tracker
      output :tracker

      def call
        agent_name = prefixed_name("sdlc_implementor")
        log_actor("Implementing plan (agent: #{agent_name})")
        Adw::Tracker.update(tracker, issue_number, "implementing", logger)

        request = Adw::AgentTemplateRequest.new(
          agent_name: agent_name,
          slash_command: "/implement",
          args: [plan_path],
          issue_number: issue_number,
          adw_id: adw_id,
          model: "sonnet",
          cwd: worktree_path
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
