# frozen_string_literal: true

require "open3"

module Adw
  module Actors
    class DestroyWorktree < Actor
      include Adw::Actors::PipelineInputs

      input :tracker
      output :tracker

      def call
        worktree_path = tracker[:worktree_path]

        unless worktree_path && Dir.exist?(worktree_path)
          logger.info("[DestroyWorktree] No active worktree found, skipping")
          return
        end

        log_actor("Destroying worktree: #{worktree_path}")

        script = File.join(Adw.project_root, "adws", "bin", "worktree_destroy")
        _, stderr, status = Open3.capture3(script, worktree_path)

        unless status.success?
          logger.warn("[DestroyWorktree] Destroy had issues (non-blocking): #{stderr.strip}")
        end

        tracker.delete(:worktree_path)
        tracker.delete(:backend_port)
        tracker.delete(:frontend_port)
        tracker.delete(:postgres_port)
        tracker.delete(:compose_project)
        Adw::Tracker.save(issue_number, tracker)

        logger.info("Worktree destroyed: #{worktree_path}")
      end
    end
  end
end
