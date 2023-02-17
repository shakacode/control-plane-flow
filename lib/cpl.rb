# frozen_string_literal: true

require "dotenv/load"
require "cgi"
require "json"
require "net/http"
require "pathname"
require "tempfile"
require "thor"
require "yaml"

modules = Dir["#{__dir__}/**/*.rb"].reject { |file| file == __FILE__ || file.end_with?("main.rb") }
modules.sort.each { require(_1) }

# Fix for https://github.com/erikhuda/thor/issues/398
# Copied from https://github.com/rails/thor/issues/398#issuecomment-622988390
class Thor
  module Shell
    class Basic
      def print_wrapped(message, options = {})
        indent = (options[:indent] || 0).to_i
        if indent.zero?
          stdout.puts(message)
        else
          message.each_line do |message_line|
            stdout.print(" " * indent)
            stdout.puts(message_line.chomp)
          end
        end
      end
    end
  end
end

module Cpl
  class Error < StandardError; end

  class Cli < Thor
    package_name "cpl"

    # Needed to silence deprecation warning
    def self.exit_on_failure?
      true
    end

    # Needed to be able to use "run" as a command
    def self.is_thor_reserved_word?(word, type) # rubocop:disable Naming/PredicateName
      return false if word == "run"

      super(word, type)
    end

    def self.deprecated_commands
      {
        build: ::Command::BuildImage,
        promote: ::Command::PromoteImage,
        runner: ::Command::RunDetached
      }
    end

    def self.all_base_commands
      ::Command::Base.all_commands.merge(deprecated_commands)
    end

    all_base_commands.each do |command_key, command_class| # rubocop:disable Metrics/BlockLength
      deprecated = deprecated_commands[command_key]

      name = command_class::NAME
      name_for_method = deprecated ? command_key : name.tr("-", "_")
      usage = command_class::USAGE.empty? ? name : command_class::USAGE
      requires_args = command_class::REQUIRES_ARGS
      command_options = command_class::OPTIONS
      description = command_class::DESCRIPTION
      long_description = command_class::LONG_DESCRIPTION
      examples = command_class::EXAMPLES
      hide = command_class::HIDE || deprecated

      long_description += "\n#{examples}" unless examples.empty?

      # `handle_argument_error` does not exist in the context below,
      # so we store it here to be able to use it
      raise_args_error = ->(*args) { handle_argument_error(commands[name_for_method], ArgumentError, *args) }

      desc(usage, description, hide: hide)
      long_desc(long_description)
      unless command_options.empty?
        command_options.each do |option|
          method_option(option[:name], **option[:params])
        end
      end
      define_method(name_for_method) do |*args|
        if deprecated
          logger = $stderr
          logger.puts("DEPRECATED: command '#{command_key}' is deprecated, use '#{name}' instead\n")
        end

        raise_args_error.call(args, nil) if (args.empty? && requires_args) || (!args.empty? && !requires_args)

        config = Config.new(args, options)

        command_class.new(config).call
      end
    rescue StandardError => e
      logger = $stderr
      logger.puts("Unable to load command: #{e.message}")
    end
  end
end

# nice Ctrl+C
trap "INT" do
  puts
  exit(1)
end
