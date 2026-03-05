# frozen_string_literal: true

module Adw
  module Actors
    class InitializeIssueTracker < Actor
      include Adw::Actors::PipelineInputs
      input :branch_name, default: -> { nil }
      input :workflow_type, default: -> { "full_pipeline" }
      output :issue_tracker

      def call
        log_actor("Initializing issue tracker")

        # Load or create issue tracker
        loaded_issue = Adw::Tracker::Issue.load(issue_number) || {}
        loaded_issue[:branch_name] = branch_name if branch_name

        # Register workflow in issue tracker and sync to GitHub
        # (creates the issue comment BEFORE any workflow comment)
        Adw::Tracker::Issue.add_workflow(loaded_issue, adw_id: adw_id, type: workflow_type)
        Adw::Tracker::Issue.sync(loaded_issue, issue_number, logger)

        self.issue_tracker = loaded_issue
      end
    end
  end
end
