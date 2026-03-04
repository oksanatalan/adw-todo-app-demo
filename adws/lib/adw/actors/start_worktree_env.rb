# frozen_string_literal: true

require "open3"

module Adw
  module Actors
    class StartWorktreeEnv < Actor
      include Adw::Actors::PipelineInputs

      input :tracker
      input :worktree_path
      output :tracker

      def call
        log_actor("Starting worktree environment: #{worktree_path}")
        Adw::Tracker.update(tracker, issue_number, "setting_up", logger)

        script = File.join(Adw.project_root, "adws", "bin", "worktree_start")
        _, stderr, status = Open3.capture3(script, worktree_path)

        unless status.success?
          logger.warn("[StartWorktreeEnv] Services failed to start (non-blocking): #{stderr.strip}")
        end
      rescue => e
        logger.warn("[StartWorktreeEnv] Exception starting services (non-blocking): #{e.message}")
      end
    end
  end
end
