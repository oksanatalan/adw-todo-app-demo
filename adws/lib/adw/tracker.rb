# frozen_string_literal: true

require "yaml"
require "fileutils"

module Adw
  module Tracker
    STATUS_EMOJIS = {
      "classifying" => "🏷️",
      "creating_worktree" => "🌿",
      "isolating" => "🔌",
      "setting_up" => "📦",
      "starting" => "🚀",
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
      "adw/classifying"        => "C2E0C6",
      "adw/creating_worktree"  => "B2DFDB",
      "adw/isolating"          => "C3E6CB",
      "adw/setting_up"         => "A5D6A7",
      "adw/starting"           => "81C784",
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
        if tracker[:worktree_path]
          lines << "| **Worktree** | `#{File.basename(tracker[:worktree_path])}` |"
          lines << "| **Backend** | http://localhost:#{tracker[:backend_port]} |"
          lines << "| **Frontend** | http://localhost:#{tracker[:frontend_port]} |"
          lines << "| **Postgres** | localhost:#{tracker[:postgres_port]} (#{tracker[:compose_project]}) |"
        end
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
        if tracker[:_type] == :patch
          update_patch(tracker, issue_number, new_status, logger)
          return
        end

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
        if tracker[:_type] == :patch
          save_patch(issue_number, tracker[:adw_id], tracker)
          return
        end

        dir = tracker_dir(issue_number)
        FileUtils.mkdir_p(dir)

        data = {
          "comment_id" => tracker[:comment_id],
          "adw_id" => tracker[:adw_id],
          "classification" => tracker[:classification],
          "branch_name" => tracker[:branch_name],
          "status" => tracker[:status],
          "patches" => (tracker[:patches] || []).map { |p| p.transform_keys(&:to_s) },
          "phase_comments" => (tracker[:phase_comments] || {}),
          "worktree_path"   => tracker[:worktree_path],
          "backend_port"    => tracker[:backend_port],
          "frontend_port"   => tracker[:frontend_port],
          "postgres_port"   => tracker[:postgres_port],
          "compose_project" => tracker[:compose_project]
        }

        File.write(File.join(dir, "tracker.yaml"), YAML.dump(data))
      end

      def load(issue_number)
        dir = tracker_dir(issue_number)
        yaml_path = File.join(dir, "tracker.yaml")
        md_path   = File.join(dir, "tracker.md")

        if File.exist?(yaml_path)
          raw = File.read(yaml_path)
        elsif File.exist?(md_path)
          raw = File.read(md_path)
          migrate = true
        else
          return nil
        end

        data = YAML.safe_load(raw)
        return nil unless data.is_a?(Hash)

        tracker = {
          comment_id: data["comment_id"],
          adw_id: data["adw_id"],
          classification: data["classification"],
          branch_name: data["branch_name"],
          status: data["status"],
          patches: (data["patches"] || []).map { |p| p.transform_keys(&:to_sym) },
          phase_comments: (data["phase_comments"] || {}),
          worktree_path:   data["worktree_path"],
          backend_port:    data["backend_port"],
          frontend_port:   data["frontend_port"],
          postgres_port:   data["postgres_port"],
          compose_project: data["compose_project"]
        }

        if migrate
          save(issue_number, tracker)
          File.delete(md_path)
        end

        tracker
      rescue Errno::ENOENT, Psych::SyntaxError
        nil
      end

      def set_phase_comment(tracker, phase, comment_id)
        return unless comment_id

        tracker[:phase_comments] ||= {}
        tracker[:phase_comments][phase.to_s] = comment_id
      end

      def add_patch(tracker, patch_file, plan_comment_id, patch_tracker_comment_id, patch_adw_id, logger)
        tracker[:patches] ||= []
        tracker[:patches] << {
          file: patch_file,
          comment_id: plan_comment_id,
          tracker_comment_id: patch_tracker_comment_id,
          adw_id: patch_adw_id
        }
        logger.info("Patch registered in tracker: #{patch_file}")
      end

      def render_patch_comment(patch_tracker)
        emoji = STATUS_EMOJIS.fetch(patch_tracker[:status], "❓")
        trigger = patch_tracker[:trigger_comment].to_s
        trigger_preview = trigger.length > 80 ? "#{trigger[0..79]}..." : trigger

        lines = []
        lines << "## 🩹 ADW Patch Tracker"
        lines << ""
        lines << "| Field | Value |"
        lines << "|-------|-------|"
        lines << "| **ADW ID** | `#{patch_tracker[:adw_id]}` |"
        lines << "| **Status** | #{emoji} #{patch_tracker[:status]} |"
        lines << "| **Trigger** | #{trigger_preview} |"
        lines << "| **Plan** | `#{patch_tracker[:patch_file]}` |" if patch_tracker[:patch_file]
        lines << ""
        lines << COMMENT_MARKER

        lines.join("\n")
      end

      def save_patch(issue_number, adw_id, patch_tracker)
        dir = tracker_dir(issue_number)
        FileUtils.mkdir_p(dir)

        data = {
          "comment_id"      => patch_tracker[:comment_id],
          "adw_id"          => patch_tracker[:adw_id],
          "status"          => patch_tracker[:status],
          "trigger_comment" => patch_tracker[:trigger_comment],
          "patch_file"      => patch_tracker[:patch_file],
          "phase_comments"  => (patch_tracker[:phase_comments] || {})
        }

        File.write(File.join(dir, "patch-tracker-#{adw_id}.yaml"), YAML.dump(data))
      end

      def update_patch(patch_tracker, issue_number, new_status, logger)
        unless STATUSES.include?(new_status)
          raise ArgumentError, "Unknown tracker status: #{new_status}. Valid: #{STATUSES.join(', ')}"
        end

        old_status = patch_tracker[:status]
        patch_tracker[:status] = new_status

        body = render_patch_comment(patch_tracker)

        if patch_tracker[:comment_id]
          Adw::GitHub.update_issue_comment(patch_tracker[:comment_id], body)
        else
          comment_id = Adw::GitHub.create_issue_comment(issue_number, body)
          patch_tracker[:comment_id] = comment_id
        end

        old_label = old_status ? "adw/#{old_status}" : nil
        Adw::GitHub.transition_label(issue_number, "adw/#{new_status}", old_label)

        save_patch(issue_number, patch_tracker[:adw_id], patch_tracker)

        logger.info("Patch tracker updated: adw/#{new_status}")
      end

      private

      def tracker_dir(issue_number)
        project_root = Adw.project_root
        File.join(project_root, ".issues", issue_number.to_s)
      end
    end
  end
end
