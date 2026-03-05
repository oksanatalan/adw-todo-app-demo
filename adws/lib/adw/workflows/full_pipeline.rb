# frozen_string_literal: true

module Adw
  module Workflows
    class FullPipeline < Actor
      input :issue_number
      input :adw_id
      input :logger
      input :branch_name, default: -> { nil }

      play Adw::Actors::InitializeIssueTracker,
           Adw::Actors::InitializeWorkflowTracker,
           Adw::Actors::SetupEnvironment,
           Adw::Actors::FetchIssue,
           Adw::Actors::ClassifyIssue,
           Adw::Actors::BuildPlan,
           Adw::Actors::PublishPlan,
           Adw::Actors::ImplementPlan,
           Adw::Actors::TestWithResolution,
           Adw::Actors::PublishTestResults,
           Adw::Actors::ReviewCode,
           Adw::Actors::ReviewIssue,
           Adw::Actors::GenerateDocs,
           Adw::Actors::CommitChanges,
           Adw::Actors::CreatePullRequest,
           Adw::Actors::MarkDone
    end
  end
end
