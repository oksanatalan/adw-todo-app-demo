# frozen_string_literal: true

require "open3"

module Adw
  module Actors
    class InstallEnvironmentDeps < Actor
      include Adw::Actors::PipelineInputs

      input :tracker, default: -> { {} }
      output :tracker

      def call
        path = worktree_path || Adw.project_root
        log_actor("Installing dependencies in: #{path}")
        Adw::Tracker.update(tracker, issue_number, "setting_up", logger)

        script = File.join(Adw.project_root, "adws", "bin", "worktree", "setup")
        _, stderr, status = Open3.capture3(script, path)

        unless status.success?
          Adw::Tracker.update(tracker, issue_number, "error", logger)
          fail!(error: "Dependency installation failed: #{stderr.strip}")
        end

        logger.info("Dependencies installed successfully")
      end
    end
  end
end
