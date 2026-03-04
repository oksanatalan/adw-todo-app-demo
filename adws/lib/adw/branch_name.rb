# frozen_string_literal: true

module Adw
  module BranchName
    # Generate a deterministic branch name from issue metadata.
    # Format: {type}-{issue_number}-{adw_id}-{slug}
    def self.generate(issue_type, issue_number, adw_id, title)
      slug = title
        .downcase
        .gsub(/[^a-z0-9\s]/, "")
        .strip
        .split(/\s+/)
        .first(5)
        .join("-")
      slug = "task" if slug.empty?

      "#{issue_type}-#{issue_number}-#{adw_id}-#{slug}"
    end
  end
end
