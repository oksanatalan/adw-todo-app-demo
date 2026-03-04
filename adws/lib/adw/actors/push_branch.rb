# frozen_string_literal: true

require "open3"

module Adw
  module Actors
    class PushBranch < Actor
      include Adw::Actors::PipelineInputs

      input :tracker
      output :tracker

      def call
        log_actor("Pushing branch to origin")
        branch_name = tracker[:branch_name]
        unless branch_name
          fail!(error: "No branch_name in tracker, cannot push")
        end

        git_opts = worktree_path ? {chdir: worktree_path} : {}
        _stdout, stderr, status = Open3.capture3("git", "push", "origin", branch_name, **git_opts)
        unless status.success?
          Adw::Tracker.update(tracker, issue_number, "error", logger)
          fail!(error: "Git push failed: #{stderr.strip}")
        end

        logger.info("Branch #{branch_name} pushed to origin")
      end
    end
  end
end
