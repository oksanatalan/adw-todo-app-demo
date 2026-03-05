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

    ISSUE_COMMENT_MARKER = "<!-- adw_issue:v1 -->"
    WORKFLOW_COMMENT_MARKER = "<!-- adw_workflow:v1 -->"

    # Backward-compat delegations: actors calling Tracker.update/save/set_phase_comment
    # operate on workflow trackers by default.
    class << self
      def update(tracker, issue_number, new_status, logger)
        Workflow.update(tracker, issue_number, new_status, logger)
      end

      def save(issue_number, tracker)
        Workflow.save(issue_number, tracker)
      end

      def set_phase_comment(tracker, phase, comment_id)
        Workflow.set_phase_comment(tracker, phase, comment_id)
      end

      def comment_url(issue_number, comment_id)
        repo_path = Adw::GitHub.extract_repo_path(Adw::GitHub.repo_url)
        "https://github.com/#{repo_path}/issues/#{issue_number}#issuecomment-#{comment_id}"
      end
    end

    module Issue
      ISSUE_FIELDS = %w[comment_id classification branch_name worktree_path
                        backend_port frontend_port postgres_port compose_project].freeze

      class << self
        def load(issue_number)
          dir = tracker_dir(issue_number)
          issue_path = File.join(dir, "issue.yaml")

          if File.exist?(issue_path)
            load_from_yaml(issue_path)
          else
            migrate_legacy(issue_number, dir)
          end
        rescue Errno::ENOENT, Psych::SyntaxError
          nil
        end

        def save(issue_number, issue_tracker)
          dir = tracker_dir(issue_number)
          FileUtils.mkdir_p(dir)

          data = {
            "comment_id"      => issue_tracker[:comment_id],
            "classification"  => issue_tracker[:classification],
            "branch_name"     => issue_tracker[:branch_name],
            "worktree_path"   => issue_tracker[:worktree_path],
            "backend_port"    => issue_tracker[:backend_port],
            "frontend_port"   => issue_tracker[:frontend_port],
            "postgres_port"   => issue_tracker[:postgres_port],
            "compose_project" => issue_tracker[:compose_project],
            "workflows"       => (issue_tracker[:workflows] || []).map { |w| w.transform_keys(&:to_s) }
          }

          File.write(File.join(dir, "issue.yaml"), YAML.dump(data))
        end

        def render_comment(issue_tracker, issue_number = nil)
          lines = []
          lines << "## 🤖 ADW Issue"
          lines << ""
          lines << "| Field | Value |"
          lines << "|-------|-------|"
          lines << "| **Classification** | #{issue_tracker[:classification] || "pending"} |"
          lines << "| **Branch** | #{issue_tracker[:branch_name] ? "`#{issue_tracker[:branch_name]}`" : "pending"} |"
          lines << "| **Worktree** | `#{File.basename(issue_tracker[:worktree_path])}` |" if issue_tracker[:worktree_path]
          if issue_tracker[:backend_port]
            lines << "| **Backend** | http://localhost:#{issue_tracker[:backend_port]} |"
            lines << "| **Frontend** | http://localhost:#{issue_tracker[:frontend_port]} |"
            lines << "| **Postgres** | localhost:#{issue_tracker[:postgres_port]} (#{issue_tracker[:compose_project]}) |"
          end
          workflows = issue_tracker[:workflows] || []
          if workflows.any?
            lines << ""
            lines << "### Workflows"
            lines << ""
            workflows.each_with_index do |wf, idx|
              wf_tracker = issue_number && Workflow.load(issue_number, wf[:adw_id])
              if wf_tracker && wf_tracker[:comment_id]
                url = Adw::Tracker.comment_url(issue_number, wf_tracker[:comment_id])
                lines << "#{idx + 1}. [#{wf[:adw_id]}](#{url}) (#{wf[:type]})"
              else
                lines << "#{idx + 1}. `#{wf[:adw_id]}` (#{wf[:type]})"
              end
            end
          end

          lines << ""
          lines << ISSUE_COMMENT_MARKER

          lines.join("\n")
        end

        def sync(issue_tracker, issue_number, logger)
          save(issue_number, issue_tracker)

          body = render_comment(issue_tracker, issue_number)

          if issue_tracker[:comment_id]
            Adw::GitHub.update_issue_comment(issue_tracker[:comment_id], body)
          else
            comment_id = Adw::GitHub.create_issue_comment(issue_number, body)
            issue_tracker[:comment_id] = comment_id
            save(issue_number, issue_tracker)
          end

          logger.info("Issue tracker synced")
        end

        def add_workflow(issue_tracker, adw_id:, type:)
          issue_tracker[:workflows] ||= []
          issue_tracker[:workflows] << { adw_id: adw_id, type: type }
        end

        private

        def tracker_dir(issue_number)
          File.join(Adw.project_root, ".issues", issue_number.to_s)
        end

        def load_from_yaml(path)
          data = YAML.safe_load(File.read(path))
          return nil unless data.is_a?(Hash)

          {
            comment_id:      data["comment_id"],
            classification:  data["classification"],
            branch_name:     data["branch_name"],
            worktree_path:   data["worktree_path"],
            backend_port:    data["backend_port"],
            frontend_port:   data["frontend_port"],
            postgres_port:   data["postgres_port"],
            compose_project: data["compose_project"],
            workflows:       (data["workflows"] || []).map { |w| w.transform_keys(&:to_sym) }
          }
        end

        def migrate_legacy(issue_number, dir)
          yaml_path = File.join(dir, "tracker.yaml")
          md_path   = File.join(dir, "tracker.md")

          if File.exist?(yaml_path)
            source_path = yaml_path
          elsif File.exist?(md_path)
            source_path = md_path
          else
            return nil
          end

          data = YAML.safe_load(File.read(source_path))
          return nil unless data.is_a?(Hash)

          # Extract issue-level fields
          issue_tracker = {
            comment_id:      data["comment_id"],
            classification:  data["classification"],
            branch_name:     data["branch_name"],
            worktree_path:   data["worktree_path"],
            backend_port:    data["backend_port"],
            frontend_port:   data["frontend_port"],
            postgres_port:   data["postgres_port"],
            compose_project: data["compose_project"],
            workflows:       []
          }

          # Create workflow tracker from main tracker data
          if data["adw_id"]
            workflow_tracker = {
              adw_id:          data["adw_id"],
              workflow_type:   "full_pipeline",
              comment_id:      nil,
              status:          data["status"],
              plan_path:       nil,
              phase_comments:  data["phase_comments"] || {},
              trigger_comment: nil
            }
            Workflow.save(issue_number, workflow_tracker)
            add_workflow(issue_tracker, adw_id: data["adw_id"], type: "full_pipeline")
          end

          # Migrate patch trackers
          Dir.glob(File.join(dir, "patch-tracker-*.yaml")).each do |patch_path|
            patch_data = YAML.safe_load(File.read(patch_path))
            next unless patch_data.is_a?(Hash)

            patch_wf = {
              adw_id:          patch_data["adw_id"],
              workflow_type:   "patch",
              comment_id:      patch_data["comment_id"],
              status:          patch_data["status"],
              plan_path:       patch_data["patch_file"],
              phase_comments:  patch_data["phase_comments"] || {},
              trigger_comment: patch_data["trigger_comment"]
            }
            Workflow.save(issue_number, patch_wf)
            add_workflow(issue_tracker, adw_id: patch_data["adw_id"], type: "patch")
            File.delete(patch_path)
          end

          # Save new format and clean up legacy
          save(issue_number, issue_tracker)
          File.delete(source_path) if File.exist?(source_path)

          issue_tracker
        end
      end
    end

    module Workflow
      class << self
        def create(adw_id:, workflow_type:, trigger_comment: nil, plan_path: nil)
          {
            adw_id:          adw_id,
            workflow_type:   workflow_type,
            comment_id:      nil,
            status:          nil,
            plan_path:       plan_path,
            phase_comments:  {},
            trigger_comment: trigger_comment
          }
        end

        def load(issue_number, adw_id)
          dir = workflows_dir(issue_number)
          path = File.join(dir, "#{adw_id}.yaml")
          return nil unless File.exist?(path)

          data = YAML.safe_load(File.read(path))
          return nil unless data.is_a?(Hash)

          {
            adw_id:          data["adw_id"],
            workflow_type:   data["workflow_type"],
            comment_id:      data["comment_id"],
            status:          data["status"],
            plan_path:       data["plan_path"],
            phase_comments:  data["phase_comments"] || {},
            trigger_comment: data["trigger_comment"]
          }
        rescue Errno::ENOENT, Psych::SyntaxError
          nil
        end

        def save(issue_number, tracker)
          dir = workflows_dir(issue_number)
          FileUtils.mkdir_p(dir)

          data = {
            "adw_id"          => tracker[:adw_id],
            "workflow_type"   => tracker[:workflow_type],
            "comment_id"      => tracker[:comment_id],
            "status"          => tracker[:status],
            "plan_path"       => tracker[:plan_path],
            "phase_comments"  => tracker[:phase_comments] || {},
            "trigger_comment" => tracker[:trigger_comment]
          }

          File.write(File.join(dir, "#{tracker[:adw_id]}.yaml"), YAML.dump(data))
        end

        def render_comment(tracker, issue_number = nil)
          emoji = STATUS_EMOJIS.fetch(tracker[:status], "❓")

          lines = []
          lines << "## 🤖 ADW Workflow"
          lines << ""
          lines << "| Field | Value |"
          lines << "|-------|-------|"
          lines << "| **ADW ID** | `#{tracker[:adw_id]}` |"
          lines << "| **Type** | #{tracker[:workflow_type]} |"
          lines << "| **Status** | #{emoji} #{tracker[:status]} |"
          if tracker[:trigger_comment]
            trigger = tracker[:trigger_comment].to_s
            trigger_preview = trigger.length > 80 ? "#{trigger[0..79]}..." : trigger
            lines << "| **Trigger** | #{trigger_preview} |"
          end
          plan_comment_id = tracker[:phase_comments] && tracker[:phase_comments]["plan"]
          if plan_comment_id && issue_number
            plan_url = comment_url(issue_number, plan_comment_id)
            lines << "| **Plan** | [View plan](#{plan_url}) |"
          elsif tracker[:plan_path]
            lines << "| **Plan** | `#{tracker[:plan_path]}` |"
          end
          lines << ""
          lines << WORKFLOW_COMMENT_MARKER

          lines.join("\n")
        end

        def update(tracker, issue_number, new_status, logger)
          unless STATUSES.include?(new_status)
            raise ArgumentError, "Unknown tracker status: #{new_status}. Valid: #{STATUSES.join(', ')}"
          end

          old_status = tracker[:status]
          tracker[:status] = new_status

          body = render_comment(tracker, issue_number)

          if tracker[:comment_id]
            Adw::GitHub.update_issue_comment(tracker[:comment_id], body)
          else
            comment_id = Adw::GitHub.create_issue_comment(issue_number, body)
            tracker[:comment_id] = comment_id
          end

          old_label = old_status ? "adw/#{old_status}" : nil
          Adw::GitHub.transition_label(issue_number, "adw/#{new_status}", old_label)

          save(issue_number, tracker)

          logger.info("Workflow tracker updated: adw/#{new_status}")
        end

        def set_phase_comment(tracker, phase, comment_id)
          return unless comment_id

          tracker[:phase_comments] ||= {}
          tracker[:phase_comments][phase.to_s] = comment_id
        end

        private

        def workflows_dir(issue_number)
          File.join(Adw.project_root, ".issues", issue_number.to_s, "workflows")
        end

        def comment_url(issue_number, comment_id)
          Adw::Tracker.comment_url(issue_number, comment_id)
        end
      end
    end
  end
end
