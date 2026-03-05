# frozen_string_literal: true

module Adw
  module Actors
    # Swaps the play chain context from main pipeline mode to patch mode.
    # After this actor runs, all downstream actors operate on the patch_tracker
    # (with _type: :patch) and use the patch-specific adw_id, logger, and agent prefix.
    class InitializePatchContext < Actor
      include Adw::Actors::PipelineInputs

      input :tracker            # main tracker (from InitializeTracker)
      input :comment_body

      output :tracker           # replaced with patch_tracker
      output :main_tracker      # preserved original for BuildPatchPlan and MarkPatchDone
      output :adw_id            # replaced with patch_adw_id
      output :logger            # replaced with patch_logger
      output :agent_name_prefix # "patch_"

      # Overrides for downstream actors
      output :commit_message    # for CommitChanges
      output :push_blocking     # for PushBranch
      output :title             # for PublishPlan

      # Test actor name overrides (TestWithResolution inputs)
      output :test_agent_name
      output :resolver_prefix
      output :ops_agent_name

      def call
        log_actor("Initializing patch context")

        # Preserve main tracker
        self.main_tracker = tracker

        # Create patch identity
        patch_adw_id = Adw::Utils.make_adw_id
        patch_logger = Adw::Utils.setup_logger(issue_number, patch_adw_id, "adw_patch")

        # Create patch tracker with polymorphic type
        patch_tracker = {
          _type: :patch,
          adw_id: patch_adw_id,
          branch_name: tracker[:branch_name],
          status: nil,
          trigger_comment: comment_body,
          patch_file: nil,
          phase_comments: {}
        }

        # Transition both trackers
        Adw::Tracker.update(tracker, issue_number, "patching", logger)
        Adw::Tracker.update_patch(patch_tracker, issue_number, "patching", patch_logger)

        # Swap context for downstream actors
        self.tracker = patch_tracker
        self.adw_id = patch_adw_id
        self.logger = patch_logger
        self.agent_name_prefix = "patch_"

        # Configure downstream actors
        self.commit_message = "patch: apply human feedback for ##{issue_number}"
        self.push_blocking = false
        self.title = "Patch Plan"

        # Test actor overrides
        self.test_agent_name = "patch_test_runner"
        self.resolver_prefix = "patch_test_resolver"
        self.ops_agent_name = "patch_ops"

        patch_logger.info("Patch context initialized: patch_adw_id=#{patch_adw_id}")
      end
    end
  end
end
