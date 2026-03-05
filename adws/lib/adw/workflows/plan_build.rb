# frozen_string_literal: true

module Adw
  module Workflows
    class PlanBuild < Actor
      input :issue_number
      input :adw_id
      input :logger

      play Adw::Actors::InitializeIssueTracker,
           Adw::Actors::InitializeWorkflowTracker,
           Adw::Actors::FetchIssue,
           Adw::Actors::ClassifyIssue,
           Adw::Actors::CreateBranch,
           Adw::Actors::BuildPlan,
           Adw::Actors::PublishPlan,
           Adw::Actors::ImplementPlan
    end
  end
end
