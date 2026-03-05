# frozen_string_literal: true
module Adw
  module Actors
    class InitializeTracker < Actor
      include Adw::Actors::PipelineInputs
      input :branch_name, default: -> { nil }
      output :tracker

      def call
        log_actor("Initializing tracker")
        loaded = Adw::Tracker.load(issue_number) || {}
        merge_data = { adw_id: adw_id }
        merge_data[:branch_name] = branch_name if branch_name
        self.tracker = loaded.merge(merge_data)
      end
    end
  end
end
