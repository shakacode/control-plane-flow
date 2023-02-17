# frozen_string_literal: true

require "dotenv/load"
require "cgi"
require "json"
require "net/http"
require "optparse"
require "pathname"
require "tempfile"
require "yaml"

modules = Dir["#{__dir__}/**/*.rb"].reject { |file| file == __FILE__ || file.end_with?("main.rb") }
modules.sort.each { require(_1) }

module Cpl
  class Error < StandardError; end

  class Cli
    def initialize # rubocop:disable Metrics/MethodLength
      config = Config.new
      commands = Command::Base.all_commands

      deprecated = {
        build: "build-image",
        promote: "promote-image",
        runner: "run:detached"
      }[config.cmd]

      if deprecated
        logger = $stderr
        logger.puts("DEPRECATED: command '#{config.cmd_untranslated}' is deprecated, use '#{deprecated}' instead\n")
        command = deprecated.tr(":-", "_").to_sym
      end

      command ||= config.cmd

      abort("ERROR: Unknown command '#{config.cmd_untranslated}'") unless commands[command]

      # nice Ctrl+C
      trap "INT" do
        puts
        exit(1)
      end

      commands[command].new(config).call
    end
  end
end
