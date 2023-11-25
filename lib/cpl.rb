# frozen_string_literal: true

require "dotenv/load"
require "cgi"
require "json"
require "net/http"
require "pathname"
require "tempfile"
require "thor"
require "yaml"

# We need to require base before all commands, since the commands inherit from it
require_relative "command/base"

modules = Dir["#{__dir__}/**/*.rb"].reject do |file|
  file == __FILE__ || file.end_with?("base.rb")
end
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

  class Cli < Thor # rubocop:disable Metrics/ClassLength
    package_name "cpl"
    default_task :no_command

    def self.start(*args)
      check_cpln_version
      check_cpl_version
      fix_help_option

      super(*args)
    end

    def self.check_cpln_version # rubocop:disable Metrics/MethodLength
      return if @checked_cpln_version

      @checked_cpln_version = true

      result = `cpln --version 2>/dev/null`
      if $CHILD_STATUS.success?
        data = JSON.parse(result)

        version = data["npm"]
        min_version = Cpl::MIN_CPLN_VERSION
        if Gem::Version.new(version) < Gem::Version.new(min_version)
          ::Shell.abort("Current 'cpln' version: #{version}. Minimum supported version: #{min_version}. " \
                        "Please update it with 'npm update -g @controlplane/cli'.")
        end
      else
        ::Shell.abort("Can't find 'cpln' executable. Please install it with 'npm install -g @controlplane/cli'.")
      end
    end

    def self.check_cpl_version # rubocop:disable Metrics/MethodLength
      return if @checked_cpl_version

      @checked_cpl_version = true

      result = `gem search ^cpl$ --remote 2>/dev/null`
      return unless $CHILD_STATUS.success?

      matches = result.match(/cpl \((.+)\)/)
      return unless matches

      version = Cpl::VERSION
      latest_version = matches[1]
      return unless Gem::Version.new(version) < Gem::Version.new(latest_version)

      ::Shell.warn("You are not using the latest 'cpl' version. Please update it with 'gem update cpl'.")
      $stderr.puts
    end

    # This is so that we're able to run `cpl COMMAND --help` to print the help
    # (it basically changes it to `cpl --help COMMAND`, which Thor recognizes)
    # Based on https://stackoverflow.com/questions/49042591/how-to-add-help-h-flag-to-thor-command
    def self.fix_help_option
      help_mappings = Thor::HELP_MAPPINGS + ["help"]
      matches = help_mappings & ARGV
      matches.each do |match|
        ARGV.delete(match)
        ARGV.unshift(match)
      end
    end

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
      @deprecated_commands ||= begin
        deprecated_commands_file_path = "#{__dir__}/deprecated_commands.json"
        deprecated_commands_data = File.binread(deprecated_commands_file_path)
        deprecated_commands = JSON.parse(deprecated_commands_data)
        deprecated_commands.to_h do |old_command_name, new_command_name|
          file_name = new_command_name.gsub(/[^A-Za-z]/, "_")
          class_name = file_name.split("_").map(&:capitalize).join

          [old_command_name, Object.const_get("::Command::#{class_name}")]
        end
      end
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
      default_args = command_class::DEFAULT_ARGS
      command_options = command_class::OPTIONS + ::Command::Base.common_options
      description = command_class::DESCRIPTION
      long_description = command_class::LONG_DESCRIPTION
      examples = command_class::EXAMPLES
      hide = command_class::HIDE || deprecated
      with_info_header = command_class::WITH_INFO_HEADER

      long_description += "\n#{examples}" if examples.length.positive?

      # `handle_argument_error` does not exist in the context below,
      # so we store it here to be able to use it
      raise_args_error = ->(*args) { handle_argument_error(commands[name_for_method], ArgumentError, *args) }

      desc(usage, description, hide: hide)
      long_desc(long_description)

      command_options.each do |option|
        method_option(option[:name], **option[:params])
      end

      # We'll handle required options manually in `Config`
      required_options = command_options.select { |option| option[:params][:required] }.map { |option| option[:name] }
      disable_required_check! name_for_method.to_sym if required_options.any?

      define_method(name_for_method) do |*provided_args| # rubocop:disable Metrics/MethodLength
        if deprecated
          ::Shell.warn_deprecated("Command '#{command_key}' is deprecated, " \
                                  "please use '#{name}' instead.")
          $stderr.puts
        end

        args = if provided_args.length.positive?
                 provided_args
               else
                 default_args
               end

        raise_args_error.call(args, nil) if (args.empty? && requires_args) || (!args.empty? && !requires_args)

        begin
          config = Config.new(args, options, required_options)

          Cpl::Cli.show_info_header(config) if with_info_header

          command_class.new(config).call
        rescue RuntimeError => e
          ::Shell.abort(e.message)
        end
      end
    rescue StandardError => e
      ::Shell.abort("Unable to load command: #{e.message}")
    end

    def self.show_info_header(config)
      return if @showed_info_header

      rows = {}
      rows["ORG"] = config.org || "NOT PROVIDED!"
      rows["APP"] = config.app || "NOT PROVIDED!"

      rows.each do |key, value|
        puts "#{key}: #{value}"
      end

      @showed_info_header = true

      # Add a newline after the info header
      puts
    end
  end
end

# nice Ctrl+C
trap "INT" do
  puts
  exit(1)
end
