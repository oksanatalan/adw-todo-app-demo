# frozen_string_literal: true
module Adw
  module Actors
    class BuildPlan < Actor
      include Adw::Actors::PipelineInputs
      input :issue
      input :issue_command
      input :tracker
      output :tracker
      output :plan_path

      def call
        log_actor("Building plan (agent: sdlc_planner)")
        path = Adw::PipelineHelpers.plan_path_for(issue_number)
        Adw::Tracker.update(tracker, issue_number, "planning", logger)

        request = Adw::AgentTemplateRequest.new(
          agent_name: "sdlc_planner",
          slash_command: issue_command,
          args: [path, "#{issue.title}: #{issue.body}"],
          issue_number: issue_number,
          adw_id: adw_id,
          model: "opus",
          cwd: worktree_path
        )

        response = Adw::Agent.execute_template(request)

        unless response.success
          Adw::Tracker.update(tracker, issue_number, "error", logger)
          fail!(error: "Plan build failed: #{response.output}")
        end

        self.plan_path = path
        logger.info("Plan created at: #{path}")
      end
    end
  end
end
