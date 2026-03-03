# frozen_string_literal: true

require "dotenv"
Dotenv.load(File.join(__dir__, "../.env"))

module Adw
  def self.project_root
    @project_root ||= File.dirname(File.dirname(__dir__))
  end
end

require_relative "adw/data_types"
require_relative "adw/utils"
require_relative "adw/github"
require_relative "adw/tracker"
require_relative "adw/agent"
require_relative "adw/pipeline_helpers"
require_relative "adw/r2"
