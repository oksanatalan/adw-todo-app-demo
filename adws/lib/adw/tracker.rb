# frozen_string_literal: true

require "yaml"
require "fileutils"

module Adw
  module Tracker
    STATUS_EMOJIS = {
      "classifying" => "🏷️",
      "planning" => "📋",
      "implementing" => "🔨",
      "testing" => "🧪",
      "reviewing" => "🔍",
      "reviewing_issue" => "📸",
      "documenting" => "📝",
      "patching" => "🩹",
      "committing" => "💾",
      "creating_pr" => "🔗",
      "done" => "✅",
      "error" => "❌"
    }.freeze

    STATUSES = STATUS_EMOJIS.keys.freeze

    COMMENT_MARKER = "<!-- adw_tracker:v1 -->"

    LABEL_COLORS = {
      "adw/classifying"  => "C2E0C6",
      "adw/planning"     => "BFD4F2",
      "adw/implementing" => "FEF2C0",
      "adw/testing"      => "D4E157",
      "adw/reviewing"    => "F9A825",
      "adw/reviewing_issue" => "E1BEE7",
      "adw/documenting"  => "90CAF9",
      "adw/patching"     => "FBCA04",
      "adw/committing"   => "D4C5F9",
      "adw/creating_pr"  => "BFDADC",
      "adw/done"         => "0E8A16",
      "adw/error"        => "E11D48"
    }.freeze

    class << self
      def render_comment(tracker)
        emoji = STATUS_EMOJIS.fetch(tracker[:status], "❓")

        lines = []
        lines << "## 🤖 ADW Tracker"
        lines << ""
        lines << "| Field | Value |"
        lines << "|-------|-------|"
        lines << "| **ADW ID** | `#{tracker[:adw_id]}` |"
        lines << "| **Status** | #{emoji} #{tracker[:status]} |"
        lines << "| **Classification** | #{tracker[:classification] || "pending"} |"
        lines << "| **Branch** | #{tracker[:branch_name] ? "`#{tracker[:branch_name]}`" : "pending"} |"
        patches = tracker[:patches] || []
        if patches.any?
          lines << ""
          lines << "### Patches"
          lines << ""
          patches.each_with_index do |patch, idx|
            file_name = File.basename(patch[:file] || "unknown")
            lines << "#{idx + 1}. `#{file_name}`"
          end
        end

        lines << ""
        lines << COMMENT_MARKER

        lines.join("\n")
      end

      def update(tracker, issue_number, new_status, logger)
        unless STATUSES.include?(new_status)
          raise ArgumentError, "Unknown tracker status: #{new_status}. Valid: #{STATUSES.join(', ')}"
        end

        old_status = tracker[:status]
        tracker[:status] = new_status

        body = render_comment(tracker)

        if tracker[:comment_id]
          Adw::GitHub.update_issue_comment(tracker[:comment_id], body)
        else
          comment_id = Adw::GitHub.create_issue_comment(issue_number, body)
          tracker[:comment_id] = comment_id
        end

        # Transition label
        old_label = old_status ? "adw/#{old_status}" : nil
        Adw::GitHub.transition_label(issue_number, "adw/#{new_status}", old_label)

        # Persist tracker to disk
        save(issue_number, tracker)

        logger.info("Tracker updated: adw/#{new_status}")
      end

      def save(issue_number, tracker)
        dir = tracker_dir(issue_number)
        FileUtils.mkdir_p(dir)

        data = {
          "comment_id" => tracker[:comment_id],
          "adw_id" => tracker[:adw_id],
          "classification" => tracker[:classification],
          "branch_name" => tracker[:branch_name],
          "status" => tracker[:status],
          "patches" => (tracker[:patches] || []).map { |p| p.transform_keys(&:to_s) },
          "phase_comments" => (tracker[:phase_comments] || {})
        }

        content = "#{YAML.dump(data)}---\n"
        File.write(File.join(dir, "tracker.md"), content)
      end

      def load(issue_number)
        path = File.join(tracker_dir(issue_number), "tracker.md")
        raw = File.read(path)
        data = YAML.safe_load(raw)
        return nil unless data.is_a?(Hash)

        {
          comment_id: data["comment_id"],
          adw_id: data["adw_id"],
          classification: data["classification"],
          branch_name: data["branch_name"],
          status: data["status"],
          patches: (data["patches"] || []).map { |p| p.transform_keys(&:to_sym) },
          phase_comments: (data["phase_comments"] || {})
        }
      rescue Errno::ENOENT, Psych::SyntaxError
        nil
      end

      def set_phase_comment(tracker, phase, comment_id)
        return unless comment_id

        tracker[:phase_comments] ||= {}
        tracker[:phase_comments][phase.to_s] = comment_id
      end

      def add_patch(tracker, patch_file, comment_id, logger)
        tracker[:patches] ||= []
        tracker[:patches] << { file: patch_file, comment_id: comment_id }
        logger.info("Patch registered in tracker: #{patch_file}")
      end

      private

      def tracker_dir(issue_number)
        project_root = Adw.project_root
        File.join(project_root, ".issues", issue_number.to_s)
      end
    end
  end
end
