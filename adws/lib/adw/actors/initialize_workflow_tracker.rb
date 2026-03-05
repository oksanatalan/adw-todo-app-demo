# frozen_string_literal: true

module Adw
  module Actors
    class InitializeWorkflowTracker < Actor
      include Adw::Actors::PipelineInputs
      input :workflow_type, default: -> { "full_pipeline" }
      input :trigger_comment, default: -> { nil }
      output :tracker

      def call
        log_actor("Initializing workflow tracker")

        self.tracker = Adw::Tracker::Workflow.create(
          adw_id: adw_id,
          workflow_type: workflow_type,
          trigger_comment: trigger_comment
        )
      end
    end
  end
end
