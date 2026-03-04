# frozen_string_literal: true

require "open3"

module Adw
  module Actors
    class CommitChanges < Actor
      include Adw::Actors::PipelineInputs

      input :issue
      input :tracker
      output :tracker

      def call
        log_actor("Committing changes (agent: pipeline_committer)")
        Adw::Tracker.update(tracker, issue_number, "committing", logger)

        git_opts = worktree_path ? {chdir: worktree_path} : {}
        stdout, _, status = Open3.capture3("git", "status", "--porcelain", **git_opts)
        if status.success? && stdout.strip.empty?
          logger.info("No pending changes to commit")
          return
        end

        issue_class = tracker[:classification] || "/chore"
        issue_type = issue_class.delete_prefix("/")

        request = Adw::AgentTemplateRequest.new(
          agent_name: "pipeline_committer",
          slash_command: "/git:commit",
          args: ["-m", "\"#{issue_type}: implement, test, review and document ##{issue.number}\""],
          issue_number: issue_number,
          adw_id: adw_id,
          model: "sonnet",
          cwd: worktree_path
        )

        response = Adw::Agent.execute_template(request)
        unless response.success
          Adw::Tracker.update(tracker, issue_number, "error", logger)
          fail!(error: "Commit failed: #{response.output}")
        end

        logger.info("Changes committed")
      end
    end
  end
end
