# frozen_string_literal: true

module Adw
  module Actors
    # Shared input declarations for all ADW pipeline actors.
    # Include this module to get common inputs and the prefixed_name helper.
    module PipelineInputs
      def self.included(base)
        base.input :issue_number
        base.input :adw_id
        base.input :logger
        base.input :worktree_path, default: -> { nil }
        base.input :agent_name_prefix, default: -> { "" }
      end

      def log_actor(msg = "Starting")
        actor_name = self.class.name.split("::").last
        logger.info("[#{actor_name}] #{msg}")
      end

      def prefixed_name(base_name)
        "#{agent_name_prefix}#{base_name}"
      end
    end
  end
end
