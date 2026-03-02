# frozen_string_literal: true

require "open3"
require "json"

module Adw
  module GitHub
    class << self
      def github_env
        project_bin = File.join(Adw.project_root, "bin")
        {
          "PATH" => "#{project_bin}:#{ENV.fetch('PATH', '')}"
        }
      end

      def repo_url
        @repo_url ||= begin
          stdout, stderr, status = Open3.capture3("git", "remote", "get-url", "origin")
          unless status.success?
            raise "No git remote 'origin' found. Please ensure you're in a git repository with a remote. #{stderr}"
          end

          stdout.strip
        end
      end

      def extract_repo_path(url)
        url.sub(%r{\Ahttps://github\.com/}, "")
           .sub(%r{\Agit@github\.com:}, "")
           .sub(/\.git\z/, "")
      end

      def fetch_issue(issue_number, repo_path)
        cmd = [
          "gh", "issue", "view", issue_number.to_s,
          "-R", repo_path,
          "--json", "number,title,body,state,author,assignees,labels,milestone,comments,createdAt,updatedAt,closedAt,url"
        ]

        env = github_env
        stdout, stderr, status = Open3.capture3(*([env, *cmd].compact))

        if status.success?
          issue_data = JSON.parse(stdout)
          GitHubIssue.new(issue_data)
        else
          warn stderr
          exit status.exitstatus
        end
      rescue Errno::ENOENT
        warn "Error: GitHub CLI (gh) is not available."
        warn "\nEnsure Docker is running — gh runs via bin/gh wrapper."
        warn "To authenticate: bin/gh auth login"
        exit 1
      end

      def create_issue_comment(issue_number, body)
        repo_path = extract_repo_path(repo_url)

        cmd = [
          "gh", "api",
          "repos/#{repo_path}/issues/#{issue_number}/comments",
          "--input", "-"
        ]

        env = github_env
        payload = JSON.generate({ body: body })
        stdout, stderr, status = Open3.capture3(*([env, *cmd].compact), stdin_data: payload)

        unless status.success?
          warn "Error creating comment: #{stderr}"
          return nil
        end

        data = JSON.parse(stdout)
        data["id"].to_s
      end

      def update_issue_comment(comment_id, body)
        repo_path = extract_repo_path(repo_url)

        cmd = [
          "gh", "api",
          "repos/#{repo_path}/issues/comments/#{comment_id}",
          "--method", "PATCH",
          "--input", "-"
        ]

        env = github_env
        payload = JSON.generate({ body: body })
        _stdout, stderr, status = Open3.capture3(*([env, *cmd].compact), stdin_data: payload)

        unless status.success?
          warn "Error updating comment #{comment_id}: #{stderr}"
          return false
        end

        true
      end

      def transition_label(issue_number, new_label, old_label = nil)
        repo_path = extract_repo_path(repo_url)
        env = github_env

        # Remove old label first (ignore failure if label doesn't exist)
        if old_label
          remove_cmd = [
            "gh", "issue", "edit", issue_number.to_s,
            "-R", repo_path,
            "--remove-label", old_label
          ]
          Open3.capture3(*([env, *remove_cmd].compact))
        end

        # Ensure the new label exists in the repo
        ensure_label_exists(repo_path, new_label)

        # Add new label
        add_cmd = [
          "gh", "issue", "edit", issue_number.to_s,
          "-R", repo_path,
          "--add-label", new_label
        ]

        _stdout, stderr, status = Open3.capture3(*([env, *add_cmd].compact))

        unless status.success?
          warn "Warning: Could not add label '#{new_label}': #{stderr}"
        end

        status.success?
      end

      private

      def ensure_label_exists(repo_path, label)
        color = Adw::Tracker::LABEL_COLORS.fetch(label, "EDEDED")
        cmd = ["gh", "label", "create", label, "--color", color, "--repo", repo_path, "--force"]
        env = github_env
        Open3.capture3(*([env, *cmd].compact))
      end

      public

      def fetch_open_issues(repo_path)
        cmd = [
          "gh", "issue", "list",
          "--repo", repo_path,
          "--state", "open",
          "--json", "number,title,body,labels,createdAt,updatedAt",
          "--limit", "1000"
        ]

        env = github_env
        stdout, stderr, status = Open3.capture3(*([env, *cmd].compact))

        unless status.success?
          warn "ERROR: Failed to fetch issues: #{stderr}"
          return []
        end

        issues_data = JSON.parse(stdout)
        issues = issues_data.map { |data| GitHubIssueListItem.new(data) }
        puts "Fetched #{issues.length} open issues"
        issues
      rescue JSON::ParserError => e
        warn "ERROR: Failed to parse issues JSON: #{e}"
        []
      end

      def fetch_issue_comments(repo_path, issue_number)
        cmd = [
          "gh", "issue", "view", issue_number.to_s,
          "--repo", repo_path,
          "--json", "comments"
        ]

        env = github_env
        stdout, stderr, status = Open3.capture3(*([env, *cmd].compact))

        unless status.success?
          warn "ERROR: Failed to fetch comments for issue ##{issue_number}: #{stderr}"
          return []
        end

        data = JSON.parse(stdout)
        comments = data.fetch("comments", [])
        comments.sort_by { |c| c.fetch("createdAt", "") }
      rescue JSON::ParserError => e
        warn "ERROR: Failed to parse comments JSON for issue ##{issue_number}: #{e}"
        []
      end
    end
  end
end
