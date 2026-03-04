# frozen_string_literal: true

require "open3"

module Adw
  module Actors
    class InstallWorktreeDeps < Actor
      include Adw::Actors::PipelineInputs

      input :tracker
      input :worktree_path
      output :tracker

      def call
        log_actor("Installing dependencies in worktree: #{worktree_path}")
        Adw::Tracker.update(tracker, issue_number, "installing_deps", logger)

        script = File.join(Adw.project_root, "adws", "bin", "worktree_setup")
        _, stderr, status = Open3.capture3(script, worktree_path)

        unless status.success?
          Adw::Tracker.update(tracker, issue_number, "error", logger)
          fail!(error: "Dependency installation failed: #{stderr.strip}")
        end

        logger.info("Dependencies installed successfully")
      end
    end
  end
end
