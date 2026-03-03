# frozen_string_literal: true

require "dry-struct"
require "dry-types"
require "json"

module Adw
  module Types
    include Dry.Types()
  end

  # Supported slash commands for issue classification
  ISSUE_CLASS_COMMANDS = %w[/chore /bug /feature].freeze

  class GitHubUser < Dry::Struct
    transform_keys(&:to_sym)

    attribute :login, Types::String
    attribute :name, Types::String.optional.default(nil)
  end

  class GitHubLabel < Dry::Struct
    transform_keys(&:to_sym)

    attribute :id, Types::Coercible::String
    attribute :name, Types::String
    attribute :color, Types::String
    attribute :description, Types::String.optional.default(nil)
  end

  class GitHubComment < Dry::Struct
    transform_keys do |key|
      key.to_s.gsub(/([A-Z])/) { "_#{$1.downcase}" }.to_sym
    end

    attribute :id, Types::Coercible::String
    attribute :author, GitHubUser
    attribute :body, Types::String
    attribute :created_at, Types::String
  end

  class GitHubIssueListItem < Dry::Struct
    transform_keys do |key|
      key.to_s.gsub(/([A-Z])/) { "_#{$1.downcase}" }.to_sym
    end

    attribute :number, Types::Integer
    attribute :title, Types::String
    attribute :body, Types::String
    attribute :labels, Types::Array.of(GitHubLabel).default([].freeze)
    attribute :created_at, Types::String
    attribute :updated_at, Types::String
  end

  class GitHubIssue < Dry::Struct
    transform_keys do |key|
      key.to_s.gsub(/([A-Z])/) { "_#{$1.downcase}" }.to_sym
    end

    attribute :number, Types::Integer
    attribute :title, Types::String
    attribute :body, Types::String
    attribute :state, Types::String
    attribute :author, GitHubUser
    attribute :assignees, Types::Array.of(GitHubUser).default([].freeze)
    attribute :labels, Types::Array.of(GitHubLabel).default([].freeze)
    attribute :milestone, Types::Any.optional.default(nil)
    attribute :comments, Types::Array.of(GitHubComment).default([].freeze)
    attribute :created_at, Types::String
    attribute :updated_at, Types::String
    attribute :closed_at, Types::String.optional.default(nil)
    attribute :url, Types::String

    def to_json(*_args)
      hash = {
        "number" => number,
        "title" => title,
        "body" => body,
        "state" => state,
        "author" => { "login" => author.login, "name" => author.name },
        "assignees" => assignees.map { |a| { "login" => a.login, "name" => a.name } },
        "labels" => labels.map { |l| { "id" => l.id, "name" => l.name, "color" => l.color, "description" => l.description } },
        "milestone" => milestone,
        "comments" => comments.map { |c| { "id" => c.id, "author" => { "login" => c.author.login, "name" => c.author.name }, "body" => c.body, "createdAt" => c.created_at } },
        "createdAt" => created_at,
        "updatedAt" => updated_at,
        "closedAt" => closed_at,
        "url" => url
      }
      JSON.generate(hash)
    end
  end

  class AgentPromptRequest < Dry::Struct
    transform_keys(&:to_sym)

    attribute :prompt, Types::String
    attribute :issue_number, Types::Integer
    attribute :adw_id, Types::String
    attribute :agent_name, Types::String.default("ops")
    attribute :model, Types::String.default("sonnet")
    attribute :dangerously_skip_permissions, Types::Bool.default(false)
    attribute :output_file, Types::String
  end

  class AgentPromptResponse < Dry::Struct
    transform_keys(&:to_sym)

    attribute :output, Types::String
    attribute :success, Types::Bool
    attribute :session_id, Types::String.optional.default(nil)
  end

  class AgentTemplateRequest < Dry::Struct
    transform_keys(&:to_sym)

    attribute :agent_name, Types::String
    attribute :slash_command, Types::String
    attribute :args, Types::Array.of(Types::String).default([].freeze)
    attribute :issue_number, Types::Integer
    attribute :adw_id, Types::String
    attribute :model, Types::String.default("sonnet")
  end

  class TestResult < Dry::Struct
    transform_keys(&:to_sym)

    attribute :test_name, Types::String
    attribute :passed, Types::Bool
    attribute :execution_command, Types::String
    attribute :test_purpose, Types::String
    attribute :error, Types::String.optional.default(nil)
  end
end
