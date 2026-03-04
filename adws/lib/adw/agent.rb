# frozen_string_literal: true

require "open3"
require "json"
require "fileutils"

module Adw
  module Agent
    class << self
      def claude_path
        @claude_path ||= `which claude`.strip.tap do |path|
          raise "Claude Code CLI not found in PATH" if path.empty?
        end
      end

      def check_installed
        stdout, _stderr, status = Open3.capture3(claude_path, "--version")
        return nil if status.success?

        "Error: Claude Code CLI is not installed or not working."
      rescue RuntimeError, Errno::ENOENT => e
        "Error: Claude Code CLI is not installed. #{e.message}"
      end

      def claude_env
        project_bin = File.join(Adw.project_root, "bin")
        env = {
          "CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR" => ENV.fetch("CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR", "true"),
          "HOME" => ENV["HOME"],
          "USER" => ENV["USER"],
          "PATH" => "#{project_bin}:#{ENV['PATH']}",
          "SHELL" => ENV["SHELL"],
          "TERM" => ENV["TERM"]
        }

        # Filter out nil values - exclude ANTHROPIC_API_KEY to force subscription auth
        env.compact
      end

      def save_prompt(prompt, issue_number, adw_id, agent_name = "ops")
        match = prompt.match(%r{\A(/\w+)})
        return unless match

        command_name = match[1].delete_prefix("/")

        project_root = Adw.project_root
        prompt_dir = File.join(project_root, ".issues", issue_number.to_s, "logs", adw_id, agent_name, "prompts")
        FileUtils.mkdir_p(prompt_dir)

        prompt_file = File.join(prompt_dir, "#{command_name}.txt")
        File.write(prompt_file, prompt)

        puts "Saved prompt to: #{prompt_file}"
      end

      def parse_jsonl(file_path)
        messages = []
        result_message = nil

        File.foreach(file_path) do |line|
          next if line.strip.empty?

          begin
            msg = JSON.parse(line)
            messages << msg
          rescue JSON::ParserError
            next
          end
        end

        # Find result message (last one with type "result")
        messages.reverse_each do |msg|
          if msg["type"] == "result"
            result_message = msg
            break
          end
        end

        [messages, result_message]
      rescue Errno::ENOENT => e
        warn "Error parsing JSONL file: #{e}"
        [[], nil]
      end

      def convert_jsonl_to_json(jsonl_file)
        json_file = jsonl_file.sub(/\.jsonl\z/, ".json")

        messages, = parse_jsonl(jsonl_file)

        File.write(json_file, JSON.pretty_generate(messages))
        puts "Created JSON file: #{json_file}"
        json_file
      end

      def prompt_claude_code(request)
        # Check if Claude Code CLI is installed
        error_msg = check_installed
        return AgentPromptResponse.new(output: error_msg, success: false) if error_msg

        # Save prompt before execution
        save_prompt(request.prompt, request.issue_number, request.adw_id, request.agent_name)

        # Create output directory if needed
        output_dir = File.dirname(request.output_file)
        FileUtils.mkdir_p(output_dir) unless output_dir.empty?

        # Build command
        cmd = [claude_path, "-p", request.prompt]
        cmd.push("--model", request.model)
        cmd.push("--output-format", "stream-json")
        cmd.push("--verbose")
        cmd.push("--dangerously-skip-permissions") if request.dangerously_skip_permissions

        # Set up environment
        env = claude_env

        begin
          stderr_output = ""
          exit_status = nil

          popen_opts = {}
          popen_opts[:chdir] = request.cwd if request.cwd

          File.open(request.output_file, "w") do |file|
            Open3.popen3(env, *cmd, **popen_opts) do |stdin, stdout, stderr, wait_thr|
              stdin.close # signal EOF immediately so claude doesn't wait for input
              # Drain stderr in a background thread to prevent pipe deadlock
              stderr_thread = Thread.new { stderr.read }

              # Write each JSONL line to disk immediately as it arrives
              stdout.each_line do |line|
                file.write(line)
                file.flush
              end

              stderr_output = stderr_thread.value
              exit_status = wait_thr.value
            end
          end

          unless exit_status.success?
            error_msg = "Claude Code error: #{stderr_output}"
            warn error_msg
            return AgentPromptResponse.new(output: error_msg, success: false)
          end

          puts "Output saved to: #{request.output_file}"

          # Parse the JSONL file
          messages, result_message = parse_jsonl(request.output_file)

          # Convert JSONL to JSON array file
          convert_jsonl_to_json(request.output_file)

          if result_message
            session_id = result_message["session_id"]
            is_error = result_message.fetch("is_error", false)
            result_text = result_message.fetch("result", "")

            AgentPromptResponse.new(
              output: result_text,
              success: !is_error,
              session_id: session_id
            )
          else
            raw_output = File.read(request.output_file)
            AgentPromptResponse.new(output: raw_output, success: true)
          end
        rescue => e
          error_msg = "Error executing Claude Code: #{e}"
          warn error_msg
          AgentPromptResponse.new(output: error_msg, success: false)
        end
      end

      def execute_template(request)
        # Construct prompt from slash command and args
        prompt = "#{request.slash_command} #{request.args.join(' ')}"

        # Create output directory with issue_number and adw_id at project root
        project_root = Adw.project_root
        output_dir = File.join(project_root, ".issues", request.issue_number.to_s, "logs", request.adw_id, request.agent_name)
        FileUtils.mkdir_p(output_dir)

        # Build output file path
        output_file = File.join(output_dir, "raw_output.jsonl")

        # Create prompt request with specific parameters
        prompt_request = AgentPromptRequest.new(
          prompt: prompt,
          issue_number: request.issue_number,
          adw_id: request.adw_id,
          agent_name: request.agent_name,
          model: request.model,
          dangerously_skip_permissions: true,
          output_file: output_file,
          cwd: request.cwd
        )

        # Execute and return response
        prompt_claude_code(prompt_request)
      end
    end
  end
end
