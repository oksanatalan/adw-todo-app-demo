# frozen_string_literal: true

require "yaml"
require "fileutils"

module Adw
  module Tracker
    STATUS_EMOJIS = {
      "classifying" => "🏷️",
      "planning" => "📋",
      "implementing" => "🔨",
      "committing" => "💾",
      "creating_pr" => "🔗",
      "done" => "✅",
      "error" => "❌"
    }.freeze

    STATUSES = STATUS_EMOJIS.keys.freeze

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
        lines << ""
        lines << "<!-- adw_tracker:v1 -->"

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
          "status" => tracker[:status]
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
          status: data["status"]
        }
      rescue Errno::ENOENT, Psych::SyntaxError
        nil
      end

      private

      def tracker_dir(issue_number)
        project_root = Adw.project_root
        File.join(project_root, ".issues", issue_number.to_s)
      end
    end
  end
end
