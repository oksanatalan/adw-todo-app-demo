# frozen_string_literal: true

module Adw
  module Actors
    class ReviewCode < Actor
      include Adw::Actors::PipelineInputs

      MAX_FIX_ATTEMPTS = 2

      input :issue
      input :tracker
      output :tracker
      output :review_result

      def call
        log_actor("Reviewing code (agent: #{agent_name})")
        Adw::Tracker.update(tracker, issue_number, "reviewing", logger)

        plan_path = Adw::PipelineHelpers.plan_path_for(issue_number)
        result = run_review(plan_path)

        comment = Adw::PipelineHelpers.format_review_comment(result)
        comment_id = Adw::GitHub.create_issue_comment(
          issue_number,
          Adw::PipelineHelpers.format_issue_message(adw_id, agent_name, comment)
        )
        Adw::Tracker.set_phase_comment(tracker, "review_tech", comment_id)
        Adw::Tracker.save(issue_number, tracker)

        if result[:action_required] == "fix_and_rerun"
          result = handle_fixes(result, plan_path)
        end

        self.review_result = result

        if result[:overall_severity] == "critical" && result[:action_required] == "fix_and_rerun"
          Adw::Tracker.update(tracker, issue_number, "error", logger)
          fail!(error: "Review found unresolvable critical issues: #{result[:summary]}")
        end

        logger.info("Code review completed: severity=#{result[:overall_severity]}")
      end

      private

      def agent_name
        prefixed_name("code_reviewer")
      end

      def run_review(plan_path)
        request = Adw::AgentTemplateRequest.new(
          agent_name: agent_name,
          slash_command: "/adw:review:tech",
          args: [issue.to_json, plan_path],
          issue_number: issue_number,
          adw_id: adw_id,
          model: "sonnet",
          cwd: worktree_path
        )
        response = Adw::Agent.execute_template(request)
        unless response.success
          logger.error("Review failed: #{response.output}")
          return { overall_severity: "error", action_required: "none", summary: response.output, checks: [], fix_suggestions: [] }
        end
        Adw::PipelineHelpers.parse_review_results(response.output, logger)
      end

      def handle_fixes(result, plan_path)
        attempt = 0
        while attempt < MAX_FIX_ATTEMPTS && result[:action_required] == "fix_and_rerun"
          attempt += 1
          logger.info("Review fix attempt #{attempt}/#{MAX_FIX_ATTEMPTS}")

          fix_payload = JSON.generate({
            fix_suggestions: result[:fix_suggestions],
            failed_checks: result[:checks]&.select { |c| c["result"] == "FAIL" }
          })

          fix_request = Adw::AgentTemplateRequest.new(
            agent_name: "#{agent_name}_resolver_iter#{attempt}",
            slash_command: "/adw:resolve_review_issue",
            args: [fix_payload],
            issue_number: issue_number,
            adw_id: adw_id,
            model: "sonnet",
            cwd: worktree_path
          )

          fix_response = Adw::Agent.execute_template(fix_request)
          unless fix_response.success
            logger.warn("Fix attempt #{attempt} failed: #{fix_response.output}")
            break
          end

          recheck_request = Adw::AgentTemplateRequest.new(
            agent_name: "#{agent_name}_recheck_#{attempt}",
            slash_command: "/adw:review:tech",
            args: [issue.to_json, plan_path],
            issue_number: issue_number,
            adw_id: adw_id,
            model: "sonnet",
            cwd: worktree_path
          )

          recheck_response = Adw::Agent.execute_template(recheck_request)
          if recheck_response.success
            result = Adw::PipelineHelpers.parse_review_results(recheck_response.output, logger)
            comment = Adw::PipelineHelpers.format_review_comment(result)
            Adw::GitHub.create_issue_comment(
              issue_number,
              Adw::PipelineHelpers.format_issue_message(adw_id, agent_name, "Post-fix review (attempt #{attempt}):\n#{comment}")
            )
          else
            logger.warn("Re-review failed: #{recheck_response.output}")
            break
          end
        end
        result
      end
    end
  end
end
