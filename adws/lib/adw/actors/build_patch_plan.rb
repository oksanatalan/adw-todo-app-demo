# frozen_string_literal: true

module Adw
  module Actors
    # Builds a patch plan from a human comment.
    # Expects the patch context to be already initialized (by InitializePatchContext),
    # so tracker is the patch_tracker and adw_id is the patch_adw_id.
    class BuildPatchPlan < Actor
      include Adw::Actors::PipelineInputs

      input :comment_body
      input :tracker             # patch_tracker (with _type: :patch)
      input :main_tracker, default: -> { nil }
      output :tracker
      output :main_tracker
      output :plan_path          # path to the patch plan file (for PublishPlan, ImplementPlan)

      def call
        log_actor("Building patch plan")

        patch_file = ".issues/#{issue_number}/patch-#{issue_number}-#{adw_id}.md"
        original_plan = Adw::PipelineHelpers.plan_path_for(issue_number)

        args = [comment_body, patch_file]
        args << original_plan if File.exist?(original_plan)

        request = Adw::AgentTemplateRequest.new(
          agent_name: prefixed_name("planner"),
          slash_command: "/adw:patch",
          args: args,
          issue_number: issue_number,
          adw_id: adw_id,
          model: "opus"
        )

        response = Adw::Agent.execute_template(request)

        unless response.success
          Adw::Tracker.update(tracker, issue_number, "error", logger)
          Adw::Tracker.update(main_tracker, issue_number, "done", logger) if main_tracker
          fail!(error: "Patch plan creation failed: #{response.output}")
        end

        tracker[:patch_file] = patch_file

        # Register patch in main tracker
        if main_tracker
          Adw::Tracker.add_patch(main_tracker, patch_file, nil, tracker[:comment_id], adw_id, logger)
          Adw::Tracker.save(issue_number, main_tracker)
        end

        Adw::Tracker.save(issue_number, tracker) # dispatches to save_patch via _type

        self.plan_path = patch_file
        logger.info("Patch plan created: #{patch_file}")
      end
    end
  end
end
