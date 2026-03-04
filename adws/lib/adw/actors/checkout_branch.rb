# frozen_string_literal: true

require "open3"

module Adw
  module Actors
    class CheckoutBranch < Actor
      include Adw::Actors::PipelineInputs

      input :tracker

      def call
        branch_name = tracker[:branch_name]
        unless branch_name
          fail!(error: "No branch_name in tracker")
        end

        _, stderr, status = Open3.capture3("git", "checkout", branch_name)
        unless status.success?
          fail!(error: "git checkout failed: #{stderr.strip}")
        end

        _, stderr, status = Open3.capture3("git", "pull", "origin", branch_name)
        unless status.success?
          fail!(error: "git pull failed: #{stderr.strip}")
        end

        logger.info("Checked out and rebased branch: #{branch_name}")
      end
    end
  end
end
