# frozen_string_literal: true

require "open3"
require "json"

module Adw
  module Actors
    class ConfigureWorktree < Actor
      include Adw::Actors::PipelineInputs

      input :tracker
      input :branch_name
      input :worktree_path
      output :tracker

      def call
        log_actor("Configuring worktree environment for: #{branch_name}")

        script = File.join(Adw.project_root, "adws", "bin", "worktree_configure")
        stdout, stderr, status = Open3.capture3(script, branch_name, worktree_path)

        unless status.success?
          Adw::Tracker.update(tracker, issue_number, "error", logger)
          fail!(error: "Worktree configuration failed: #{stderr.strip}")
        end

        ports = JSON.parse(stdout.strip, symbolize_names: true)
        tracker[:backend_port]    = ports[:backend_port]
        tracker[:frontend_port]   = ports[:frontend_port]
        tracker[:postgres_port]   = ports[:postgres_port]
        tracker[:compose_project] = ports[:compose_project]
        Adw::Tracker.save(issue_number, tracker)

        logger.info("Configured — backend: #{ports[:backend_port]}, frontend: #{ports[:frontend_port]}, postgres: #{ports[:postgres_port]}")
      end
    end
  end
end
