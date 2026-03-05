# frozen_string_literal: true

module Adw
  module Actors
    # Marks both the patch tracker and the main tracker as done.
    # Used as the final actor in the Patch pipeline play chain.
    class MarkPatchDone < Actor
      include Adw::Actors::PipelineInputs

      input :tracker        # patch_tracker (with _type: :patch)
      input :main_tracker   # original main tracker
      output :tracker

      def call
        log_actor("Marking patch workflow as done")
        Adw::Tracker.update(tracker, issue_number, "done", logger)
        Adw::Tracker.update(main_tracker, issue_number, "done", logger)
        logger.info("Patch workflow completed for issue ##{issue_number}")
      end
    end
  end
end
