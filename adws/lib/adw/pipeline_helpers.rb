# frozen_string_literal: true

module Adw
  module PipelineHelpers
    MAX_TEST_RETRY_ATTEMPTS = 4

    BOT_COMMENT_PATTERN = /\A\w{8}_\w+:/

    module_function

    def format_issue_message(adw_id, agent_name, message, session_id = nil)
      if session_id
        "#{adw_id}_#{agent_name}_#{session_id}: #{message}"
      else
        "#{adw_id}_#{agent_name}: #{message}"
      end
    end

    def check_error(error_or_response, issue_number, error_prefix, logger, tracker)
      error = nil

      if error_or_response.is_a?(Adw::AgentPromptResponse)
        error = error_or_response.output unless error_or_response.success
      else
        error = error_or_response
      end

      return unless error

      logger.error("#{error_prefix}: #{error}")
      Adw::Tracker.update(tracker, issue_number, "error", logger)
      exit 1
    end

    def extract_json_from_markdown(text)
      json_text = text.strip
      if json_text =~ /```(?:json)?\s*\n?(.*?)\n?\s*```/m
        json_text = $1.strip
      end
      json_text
    end

    def plan_path_for(issue_number)
      ".issues/#{issue_number}/plan.md"
    end

    def post_plan_comment(issue_number, adw_id, agent_name, file_path, title, logger)
      content = File.read(file_path)
      body = format_issue_message(
        adw_id, agent_name,
        "#{title}\n\n<details>\n<summary>#{title}</summary>\n\n#{content}\n</details>"
      )
      comment_id = Adw::GitHub.create_issue_comment(issue_number, body)
      logger.info("#{title} posted to issue ##{issue_number}")
      comment_id
    rescue Errno::ENOENT, StandardError => e
      logger.warn("Warning: Could not post #{title.downcase} to issue: #{e.message}")
      nil
    end

    def parse_test_results(output, logger)
      json_text = extract_json_from_markdown(output)

      results_data = JSON.parse(json_text)
      results = results_data.map { |r| Adw::TestResult.new(r) }

      passed_count = results.count(&:passed)
      failed_count = results.length - passed_count

      [results, passed_count, failed_count]
    rescue JSON::ParserError, Dry::Struct::Error => e
      logger.error("Error parseando resultados de tests: #{e}")
      [[], 0, 0]
    end

    def run_tests(issue_number, adw_id, logger, agent_name: "test_runner")
      log_dir = File.join(Adw.project_root, ".issues", issue_number.to_s, "logs", adw_id, agent_name)

      request = Adw::AgentTemplateRequest.new(
        agent_name: agent_name,
        slash_command: "/adw:test",
        args: [log_dir],
        issue_number: issue_number,
        adw_id: adw_id,
        model: "sonnet"
      )

      logger.debug("test_template_request: #{request.to_h}")
      response = Adw::Agent.execute_template(request)
      logger.debug("test_response: #{response.to_h}")

      response
    end

    def resolve_failed_tests(failed_tests, adw_id, issue_number, logger, agent_prefix: "test_resolver", verbose_comments: true, iteration: 1)
      resolved_count = 0
      unresolved_count = 0

      failed_tests.each_with_index do |test, idx|
        logger.info("\n=== Resolviendo test fallido #{idx + 1}/#{failed_tests.length}: #{test.test_name} ===")

        test_payload = JSON.generate(test.to_h)
        agent_name = "#{agent_prefix}_iter#{iteration}_#{idx}"

        resolve_request = Adw::AgentTemplateRequest.new(
          agent_name: agent_name,
          slash_command: "/adw:resolve_failed_test",
          args: [test_payload],
          issue_number: issue_number,
          adw_id: adw_id,
          model: "sonnet"
        )

        comment_msg = if verbose_comments
          "Intentando resolver: #{test.test_name}\n```json\n#{test_payload}\n```"
        else
          "Intentando resolver: #{test.test_name}"
        end

        Adw::GitHub.create_issue_comment(
          issue_number,
          format_issue_message(adw_id, agent_name, comment_msg)
        )

        response = Adw::Agent.execute_template(resolve_request)

        if response.success
          resolved_count += 1
          if verbose_comments
            Adw::GitHub.create_issue_comment(
              issue_number,
              format_issue_message(adw_id, agent_name, "Resuelto correctamente: #{test.test_name}")
            )
          end
          logger.info("Resuelto correctamente: #{test.test_name}")
        else
          unresolved_count += 1
          if verbose_comments
            Adw::GitHub.create_issue_comment(
              issue_number,
              format_issue_message(adw_id, agent_name, "No se pudo resolver: #{test.test_name}")
            )
          end
          logger.error("No se pudo resolver: #{test.test_name}")
        end
      end

      [resolved_count, unresolved_count]
    end

    def run_tests_with_resolution(adw_id, issue_number, logger, test_agent_name: "test_runner", resolver_prefix: "test_resolver", ops_agent_name: "ops", verbose_comments: true)
      attempt = 0
      results = []
      passed_count = 0
      failed_count = 0

      while attempt < MAX_TEST_RETRY_ATTEMPTS
        attempt += 1
        logger.info("\n=== Ejecucion de tests - Intento #{attempt}/#{MAX_TEST_RETRY_ATTEMPTS} ===")

        test_response = run_tests(issue_number, adw_id, logger, agent_name: test_agent_name)

        unless test_response.success
          logger.error("Error ejecutando tests: #{test_response.output}")
          if verbose_comments
            Adw::GitHub.create_issue_comment(
              issue_number,
              format_issue_message(adw_id, test_agent_name, "Error ejecutando tests: #{test_response.output}")
            )
          end
          break
        end

        results, passed_count, failed_count = parse_test_results(test_response.output, logger)

        if failed_count == 0
          logger.info("Todos los tests pasaron correctamente")
          break
        end

        if attempt == MAX_TEST_RETRY_ATTEMPTS
          logger.info("Alcanzado el maximo de intentos (#{MAX_TEST_RETRY_ATTEMPTS})")
          break
        end

        logger.info("\n=== Intentando resolver tests fallidos ===")
        Adw::GitHub.create_issue_comment(
          issue_number,
          format_issue_message(adw_id, ops_agent_name, "Encontrados #{failed_count} tests fallidos. Intentando resolucion...")
        )

        failed_tests = results.reject(&:passed)
        resolved, _unresolved = resolve_failed_tests(
          failed_tests, adw_id, issue_number, logger,
          agent_prefix: resolver_prefix, verbose_comments: verbose_comments, iteration: attempt
        )

        if resolved > 0
          if verbose_comments
            Adw::GitHub.create_issue_comment(
              issue_number,
              format_issue_message(adw_id, ops_agent_name, "Resueltos #{resolved}/#{failed_count} tests fallidos")
            )
          end
          logger.info("\n=== Re-ejecutando tests tras resolver #{resolved} tests ===")
        else
          logger.info("Ningun test fue resuelto, parando reintentos")
          break
        end
      end

      if attempt == MAX_TEST_RETRY_ATTEMPTS && failed_count > 0
        logger.warn("Alcanzado maximo de reintentos (#{MAX_TEST_RETRY_ATTEMPTS}) con #{failed_count} fallos pendientes")
        if verbose_comments
          Adw::GitHub.create_issue_comment(
            issue_number,
            format_issue_message(adw_id, ops_agent_name, "Alcanzado maximo de reintentos (#{MAX_TEST_RETRY_ATTEMPTS}) con #{failed_count} fallos")
          )
        end
      end

      [results, passed_count, failed_count]
    end

    def bot_comment?(body)
      body =~ BOT_COMMENT_PATTERN
    end

    def link_screenshot_urls(screenshots, review_issues)
      return unless review_issues&.any?

      url_by_path = screenshots.each_with_object({}) { |s, h| h[s["path"]] = s["url"] if s["url"] }
      review_issues.each do |item|
        item["screenshot_url"] = url_by_path[item["screenshot_path"]] if item["screenshot_path"]
      end
    end

    def parse_issue_review_results(output, logger)
      json_text = extract_json_from_markdown(output)

      data = JSON.parse(json_text)
      {
        success: data["success"],
        summary: data["summary"],
        plan_adherence: data["plan_adherence"],
        review_issues: data["review_issues"] || [],
        screenshots: data["screenshots"] || [],
        errors: data["errors"] || []
      }
    rescue JSON::ParserError => e
      logger.error("Error parseando resultados de review:issue: #{e}")
      { success: false, summary: "No se pudieron parsear los resultados", plan_adherence: nil,
        review_issues: [], screenshots: [], errors: ["JSON parse error: #{e.message}"] }
    end

    def format_evidence_comment(issue_review_result)
      parts = []
      parts << "## 📸 Evidencia Visual"
      parts << ""

      has_urls = issue_review_result[:screenshots]&.any? { |s| s["url"] }

      unless has_urls
        parts << "> ⚠️ **Las imagenes no se pudieron subir a Cloudflare R2.** Las variables de entorno CLOUDFLARE_* no estan configuradas. Los screenshots se encuentran en el directorio local del agente."
        parts << ""
      end

      parts << "**Resumen:** #{issue_review_result[:summary]}"

      if issue_review_result[:plan_adherence]
        pa = issue_review_result[:plan_adherence]
        emoji = pa["result"] == "PASS" ? "✅" : "❌"
        parts << "**Adherencia al plan:** #{emoji} #{pa['result']} - #{pa['details']}"
      end

      parts << ""

      if issue_review_result[:screenshots]&.any?
        parts << "### Capturas"
        parts << ""
        issue_review_result[:screenshots].each_with_index do |screenshot, idx|
          if has_urls && screenshot["url"]
            parts << "#### #{idx + 1}. #{screenshot['description']}"
            parts << "![#{screenshot['filename']}](#{screenshot['url']})"
            parts << ""
          else
            parts << "#{idx + 1}. **#{screenshot['description']}** → `#{screenshot['path']}`"
          end
        end
      end

      if issue_review_result[:review_issues]&.any?
        parts << ""
        parts << "### Problemas encontrados"
        parts << ""
        issue_review_result[:review_issues].each do |issue_item|
          severity_emoji = case issue_item["severity"]
                           when "blocker" then "🔴"
                           when "tech_debt" then "🟡"
                           else "🟢"
                           end
          parts << "- #{severity_emoji} **#{issue_item['description']}** (#{issue_item['severity']})"
          parts << "  - Resolucion: #{issue_item['resolution']}" if issue_item["resolution"]
          parts << "  - ![evidencia](#{issue_item['screenshot_url']})" if issue_item["screenshot_url"]
        end
      end

      if issue_review_result[:errors]&.any?
        parts << ""
        parts << "### Errores"
        issue_review_result[:errors].each { |e| parts << "- #{e}" }
      end

      parts.join("\n")
    end
  end
end
