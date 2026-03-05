# frozen_string_literal: true

module Adw
  module Workflows
    # Patch workflow for applying human feedback to completed issues.
    # Two-phase structure:
    # - Setup: fetch issue, checkout branch, classify comment
    # - Pipeline: register trackers -> plan -> implement -> test -> review -> commit -> push -> done
    #
    # Between phases, Patch.call creates a new adw_id/logger for the patch run,
    # transitions the parent tracker, and passes patch-specific overrides to Pipeline.
    class Patch < Actor
      input :issue_number
      input :adw_id
      input :logger
      input :comment_body

      output :comment_classification

      # Phase 1: Load state and classify the comment.
      class Setup < Actor
        play Adw::Actors::FetchIssue,
             Adw::Actors::CheckoutBranch,
             Adw::Actors::ClassifyComment
      end

      # Phase 2: Execute the patch pipeline (only if comment_classification == "patch")
      class Pipeline < Actor
        play Adw::Actors::InitializeIssueTracker,
             Adw::Actors::InitializeWorkflowTracker,
             Adw::Actors::BuildPatchPlan,
             Adw::Actors::PublishPlan,
             Adw::Actors::ImplementPlan,
             Adw::Actors::TestWithResolution,
             Adw::Actors::PublishTestResults,
             Adw::Actors::ReviewCode,
             Adw::Actors::ReviewIssue,
             Adw::Actors::GenerateDocs,
             Adw::Actors::CommitChanges,
             Adw::Actors::PushBranch,
             Adw::Actors::MarkDone
      end

      def call
        # Load existing trackers (no registration — that happens in Pipeline)
        issue_tracker = Adw::Tracker::Issue.load(issue_number) || {}
        tracker = Adw::Tracker::Workflow.load(issue_number, adw_id) || {}

        # Phase 1: Setup
        setup = Setup.result(
          issue_number: issue_number,
          adw_id: adw_id,
          logger: logger,
          comment_body: comment_body,
          issue_tracker: issue_tracker,
          tracker: tracker
        )
        unless setup.success?
          fail!(error: setup.error)
        end

        self.comment_classification = setup.comment_classification

        # Guard: exit gracefully if not a patch comment
        unless comment_classification == "patch"
          logger.info("Comment is not a patch (#{comment_classification.inspect}), skipping")
          Adw::GitHub.create_issue_comment(issue_number,
            Adw::PipelineHelpers.format_issue_message(adw_id, "patch_ops",
              "Comentario analizado: no requiere cambios de codigo."))
          return
        end

        # Create patch identity (new adw_id + logger for this patch run)
        patch_adw_id = Adw::Utils.make_adw_id
        patch_logger = Adw::Utils.setup_logger(issue_number, patch_adw_id, "adw_patch")

        # Transition parent workflow tracker to "patching"
        Adw::Tracker.update(setup.tracker, issue_number, "patching", logger)

        # Phase 2: Execute patch pipeline with swapped context
        pipeline = Pipeline.result(
          issue_number: issue_number,
          adw_id: patch_adw_id,
          logger: patch_logger,
          issue: setup.issue,
          comment_body: comment_body,
          worktree_path: setup.worktree_path,
          # Patch-specific overrides
          agent_name_prefix: "patch_",
          workflow_type: "patch",
          trigger_comment: comment_body,
          commit_message: "patch: apply human feedback for ##{issue_number}",
          push_blocking: false,
          title: "Patch Plan",
          test_agent_name: "patch_test_runner",
          resolver_prefix: "patch_test_resolver",
          ops_agent_name: "patch_ops"
        )

        unless pipeline.success?
          # Error recovery: restore label to done since the original work was completed
          Adw::GitHub.transition_label(issue_number, "adw/done", "adw/error")
          fail!(error: pipeline.error)
        end
      end
    end
  end
end
