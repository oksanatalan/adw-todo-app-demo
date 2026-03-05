# frozen_string_literal: true

module Adw
  module Workflows
    # Patch workflow for applying human feedback to completed issues.
    # Two-phase play chain structure consistent with FullPipeline:
    # - Setup: load tracker, fetch issue, checkout branch, classify comment
    # - Pipeline: initialize patch context → plan → implement → test → review → commit → push → done
    class Patch < Actor
      input :issue_number
      input :adw_id
      input :logger
      input :comment_body

      output :comment_classification

      # Phase 1: Load state and classify the comment
      class Setup < Actor
        play Adw::Actors::InitializeTracker,
             Adw::Actors::FetchIssue,
             Adw::Actors::CheckoutBranch,
             Adw::Actors::ClassifyComment
      end

      # Phase 2: Execute the patch pipeline (only if comment_classification == "patch")
      class Pipeline < Actor
        play Adw::Actors::InitializePatchContext,
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
             Adw::Actors::MarkPatchDone
      end

      def call
        # Phase 1: Setup
        setup = Setup.result(
          issue_number: issue_number,
          adw_id: adw_id,
          logger: logger,
          comment_body: comment_body
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

        # Phase 2: Execute patch pipeline
        pipeline = Pipeline.result(
          issue_number: issue_number,
          adw_id: adw_id,
          logger: logger,
          tracker: setup.tracker,
          issue: setup.issue,
          comment_body: comment_body,
          worktree_path: setup.worktree_path
        )

        unless pipeline.success?
          # Error recovery: restore main tracker to "done" if pipeline failed
          # (main_tracker may not be available if InitializePatchContext didn't run)
          if pipeline.respond_to?(:main_tracker) && pipeline.main_tracker
            Adw::Tracker.update(pipeline.main_tracker, issue_number, "done", logger)
          end
          fail!(error: pipeline.error)
        end
      end
    end
  end
end
