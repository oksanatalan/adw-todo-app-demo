# frozen_string_literal: true

require "securerandom"
require "logger"
require "fileutils"

module Adw
  module Utils
    # Store loggers by adw_id
    @loggers = {}

    class << self
      def make_adw_id
        SecureRandom.uuid[0..7]
      end

      def setup_logger(adw_id, trigger_type = "adw_plan_build")
        # Create log directory: adws/log/{adw_id}/{trigger_type}/
        project_root = Adw.project_root
        log_dir = File.join(project_root, "adws", "log", adw_id, trigger_type)
        FileUtils.mkdir_p(log_dir)

        log_file = File.join(log_dir, "execution.log")

        # Create logger
        logger = Logger.new(
          MultiIO.new(
            FileOutput.new(log_file),
            ConsoleOutput.new
          )
        )
        logger.level = Logger::DEBUG

        # Store logger for later retrieval
        @loggers[adw_id] = logger

        logger.info("ADW Logger initialized - ID: #{adw_id}")
        logger.debug("Log file: #{log_file}")

        logger
      end

      def get_logger(adw_id)
        @loggers[adw_id]
      end
    end

    # File output with timestamp format
    class FileOutput
      def initialize(file_path)
        @file = File.open(file_path, "a")
        @file.sync = true
      end

      def write(message)
        @file.write(message)
      end

      def close
        @file.close
      end
    end

    # Console output that strips log metadata for cleaner display
    class ConsoleOutput
      def write(message)
        # Only show INFO and above to console
        # Logger format: "S, [timestamp] SEVERITY -- : message\n"
        if message.is_a?(String)
          # Extract severity from log message
          if message =~ /\A[A-Z], \[.*?\]\s+(DEBUG)/
            return # Skip DEBUG messages on console
          end
          # Extract just the message part after " -- : "
          if message =~ / -- : (.+)/m
            $stdout.write($1)
          else
            $stdout.write(message)
          end
        end
      end

      def close
        # noop
      end
    end

    # Allows writing to multiple IO targets
    class MultiIO
      def initialize(*targets)
        @targets = targets
      end

      def write(message)
        @targets.each { |t| t.write(message) }
      end

      def close
        @targets.each(&:close)
      end
    end
  end
end
