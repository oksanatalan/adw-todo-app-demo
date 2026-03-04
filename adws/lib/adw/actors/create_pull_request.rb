# frozen_string_literal: true

module Adw
  module Actors
    class CreatePullRequest < Actor
      include Adw::Actors::PipelineInputs

      input :issue
      input :tracker
      output :tracker
      output :pr_url

      def call
        log_actor("Creating pull request (agent: pr_creator)")
        Adw::Tracker.update(tracker, issue_number, "creating_pr", logger)
        branch_name = tracker[:branch_name]

        request = Adw::AgentTemplateRequest.new(
          agent_name: "pr_creator",
          slash_command: "/adw:pull_request",
          args: [branch_name, issue.to_json, adw_id],
          issue_number: issue_number,
          adw_id: adw_id,
          model: "sonnet"
        )

        response = Adw::Agent.execute_template(request)
        unless response.success
          Adw::Tracker.update(tracker, issue_number, "error", logger)
          fail!(error: "Pull request creation failed: #{response.output}")
        end

        url = response.output.strip
        self.pr_url = url
        logger.info("Pull request created: #{url}")
      end
    end
  end
end
