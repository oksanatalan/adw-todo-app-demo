# frozen_string_literal: true

module Adw
  module Actors
    # Shared input declarations for all ADW pipeline actors.
    # Include this module to get :issue_number, :adw_id, :logger, and :worktree_path inputs.
    module PipelineInputs
      def self.included(base)
        base.input :issue_number
        base.input :adw_id
        base.input :logger
        base.input :worktree_path, default: -> { nil }
      end

      def log_actor(msg = "Starting")
        actor_name = self.class.name.split("::").last
        logger.info("[#{actor_name}] #{msg}")
      end
    end
  end
end
