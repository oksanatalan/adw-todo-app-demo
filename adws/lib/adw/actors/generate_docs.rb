# frozen_string_literal: true

require "pathname"

module Adw
  module Actors
    class GenerateDocs < Actor
      include Adw::Actors::PipelineInputs

      input :tracker
      output :tracker
      output :documentation_skipped, default: -> { false }

      def call
        log_actor("Generating documentation (agent: #{agent_name})")
        Adw::Tracker.update(tracker, issue_number, "documenting", logger)
        plan_path = Adw::PipelineHelpers.plan_path_for(issue_number)

        request = Adw::AgentTemplateRequest.new(
          agent_name: agent_name,
          slash_command: "/adw:document",
          args: [adw_id, plan_path, worktree_path].compact,
          issue_number: issue_number,
          adw_id: adw_id,
          model: "sonnet",
          cwd: worktree_path
        )

        logger.info("Running documentation generation...")
        response = Adw::Agent.execute_template(request)

        unless response.success
          logger.warn("Documentation generation failed (non-blocking): #{response.output}")
          self.documentation_skipped = true
          return
        end

        doc_path = response.output.strip
        logger.info("Documentation generated: #{doc_path}")
        post_documentation_summary(doc_path)
      rescue => e
        logger.warn("GenerateDocs actor failed non-blocking: #{e.message}")
        self.documentation_skipped = true
      end

      private

      def agent_name
        prefixed_name("documentation_generator")
      end

      def post_documentation_summary(doc_path)
        full_path = if worktree_path && !Pathname.new(doc_path).absolute?
                      File.join(worktree_path, doc_path)
                    else
                      doc_path
                    end
        content = File.read(full_path)
        parts = ["## Documentation Updated", "", "`#{doc_path}`", ""]

        if content =~ /## Overview\s*\n(.*?)(?=\n## )/m
          parts += ["### Overview", "", $1.strip, ""]
        end
        if content =~ /## Que se Construyo\s*\n(.*?)(?=\n## )/m
          parts += ["### Changes", "", $1.strip]
        end

        doc_comment_id = Adw::GitHub.create_issue_comment(
          issue_number,
          Adw::PipelineHelpers.format_issue_message(adw_id, agent_name, parts.join("\n"))
        )
        Adw::Tracker.set_phase_comment(tracker, "document", doc_comment_id)
        Adw::Tracker.save(issue_number, tracker)
        logger.info("Documentation summary posted to issue ##{issue_number}")
      rescue => e
        logger.warn("Could not post documentation summary: #{e.message}")
      end
    end
  end
end
