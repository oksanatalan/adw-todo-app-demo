# frozen_string_literal: true

require "open3"
require "fileutils"

module Adw
  module Actors
    class CreateWorktree < Actor
      include Adw::Actors::PipelineInputs

      input :issue
      input :issue_command
      input :tracker
      output :tracker
      output :branch_name
      output :worktree_path

      TREES_DIR = "trees"

      def call
        log_actor("Generating branch name and creating worktree")

        issue_type = issue_command.delete_prefix("/")

        branch_request = Adw::AgentTemplateRequest.new(
          agent_name: "branch_generator",
          slash_command: "/adw:generate_branch_name",
          args: [issue_type, adw_id, issue.to_json],
          issue_number: issue_number,
          adw_id: adw_id,
          model: "sonnet"
        )

        branch_response = Adw::Agent.execute_template(branch_request)

        unless branch_response.success
          Adw::Tracker.update(tracker, issue_number, "error", logger)
          fail!(error: "Branch name generation failed: #{branch_response.output}")
        end

        name = branch_response.output.strip
        path = File.join(Adw.project_root, TREES_DIR, name)
        FileUtils.mkdir_p(File.join(Adw.project_root, TREES_DIR))

        worktree_request = Adw::AgentTemplateRequest.new(
          agent_name: "worktree_creator",
          slash_command: "/env:worktree:create",
          args: [name],
          issue_number: issue_number,
          adw_id: adw_id,
          model: "haiku"
        )

        worktree_response = Adw::Agent.execute_template(worktree_request)

        unless worktree_response.success
          Adw::Tracker.update(tracker, issue_number, "error", logger)
          fail!(error: "Worktree creation failed: #{worktree_response.output}")
        end

        tracker[:branch_name] = name
        tracker[:worktree_path] = path
        self.branch_name = name
        self.worktree_path = path
        logger.info("Branch #{name} created, worktree at #{path}")
      end
    end
  end
end
