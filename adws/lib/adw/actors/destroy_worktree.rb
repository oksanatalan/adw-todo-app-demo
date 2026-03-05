# frozen_string_literal: true

require "open3"

module Adw
  module Actors
    class DestroyWorktree < Actor
      include Adw::Actors::PipelineInputs

      output :issue_tracker

      def call
        wt_path = issue_tracker[:worktree_path]

        unless wt_path && Dir.exist?(wt_path)
          logger.info("[DestroyWorktree] No active worktree found, skipping")
          return
        end

        log_actor("Destroying worktree: #{wt_path}")

        script = File.join(Adw.project_root, "adws", "bin", "worktree", "destroy")
        _, stderr, status = Open3.capture3(script, wt_path)

        unless status.success?
          logger.warn("[DestroyWorktree] Destroy had issues (non-blocking): #{stderr.strip}")
        end

        issue_tracker.delete(:worktree_path)
        issue_tracker.delete(:backend_port)
        issue_tracker.delete(:frontend_port)
        issue_tracker.delete(:postgres_port)
        issue_tracker.delete(:compose_project)
        Adw::Tracker::Issue.save(issue_number, issue_tracker)

        logger.info("Worktree destroyed: #{wt_path}")
      end
    end
  end
end
