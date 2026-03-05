# frozen_string_literal: true

require "open3"

module Adw
  module Actors
    class StartEnvironment < Actor
      include Adw::Actors::PipelineInputs

      input :tracker, default: -> { {} }
      output :tracker

      def call
        path = worktree_path || Adw.project_root
        log_actor("Starting environment: #{path}")
        Adw::Tracker.update(tracker, issue_number, "starting", logger)

        script = File.join(Adw.project_root, "adws", "bin", "worktree", "start")
        _, stderr, status = Open3.capture3(script, path)

        unless status.success?
          logger.warn("[StartEnvironment] Services failed to start (non-blocking): #{stderr.strip}")
        end
      rescue => e
        logger.warn("[StartEnvironment] Exception starting services (non-blocking): #{e.message}")
      end
    end
  end
end
