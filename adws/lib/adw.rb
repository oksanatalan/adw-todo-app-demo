# frozen_string_literal: true

require "dotenv"
require "service_actor"
Dotenv.load(File.join(__dir__, "../.env"))

module Adw
  def self.project_root
    @project_root ||= Dir.pwd
  end
end

require_relative "adw/data_types"
require_relative "adw/utils"
require_relative "adw/github"
require_relative "adw/tracker"
require_relative "adw/agent"
require_relative "adw/pipeline_helpers"
require_relative "adw/branch_name"
require_relative "adw/r2"

# Load actors (pipeline_inputs first; setup_environment last — depends on sub-actors)
require_relative "adw/actors/pipeline_inputs"
Dir[File.join(__dir__, "adw/actors/**/*.rb")].sort
  .reject { |f| f.end_with?("/setup_environment.rb") }
  .each { |f| require f }
require_relative "adw/actors/setup_environment"

# Load workflows (plan_build must load before compositions that depend on it)
require_relative "adw/workflows/plan_build"
Dir[File.join(__dir__, "adw/workflows/**/*.rb")].sort.each { |f| require f }
