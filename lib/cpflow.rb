# frozen_string_literal: true

require "date"
require "forwardable"
require "dotenv/load"
require "cgi"
require "json"
require "jwt"
require "net/http"
require "open3"
require "pathname"
require "tempfile"
require "thor"
require "yaml"

require_relative "constants/exit_code"

# We need to require base before all commands, since the commands inherit from it
require_relative "command/base"
require_relative "command/terraform/base"
# We need to require base terraform config before all commands, since the terraform configs inherit from it
require_relative "core/terraform_config/base"

modules = Dir["#{__dir__}/**/*.rb"].reject do |file|
  file == __FILE__ || file.end_with?("base.rb")
end
modules.sort.each { require(_1) }

# NOTE: this snippet combines all subprocesses into a group and kills all on exit to avoid hanging orphans
$child_pids = [] # rubocop:disable Style/GlobalVars
at_exit do
  $child_pids.each do |pid| # rubocop:disable Style/GlobalVars
    Process.kill("TERM", pid)
  end
end

require_relative "patches/thor"

require_relative "patches/string"

module Cpflow
  class Error < StandardError; end

  def self.root_path
    Pathname.new(File.expand_path("../", __dir__))
  end

  class Cli < Thor # rubocop:disable Metrics/ClassLength
    package_name "cpflow"
    default_task :no_command

    def self.start(*args)
      ENV["CPLN_SKIP_UPDATE_CHECK"] = "true"

      check_cpln_version
      check_cpflow_version
      fix_help_option

      super
    end

    def self.check_cpln_version # rubocop:disable Metrics/MethodLength
      return if @checked_cpln_version

      @checked_cpln_version = true

      result = ::Shell.cmd("cpln", "--version", capture_stderr: true)
      if result[:success]
        data = JSON.parse(result[:output])

        version = data["npm"]
        min_version = Cpflow::MIN_CPLN_VERSION
        if Gem::Version.new(version) < Gem::Version.new(min_version)
          ::Shell.abort("Current 'cpln' version: #{version}. Minimum supported version: #{min_version}. " \
                        "Please update it with 'npm update -g @controlplane/cli'.")
        end
      else
        ::Shell.abort("Can't find 'cpln' executable. Please install it with 'npm install -g @controlplane/cli'.")
      end
    end

    def self.check_cpflow_version # rubocop:disable Metrics/MethodLength
      return if @checked_cpflow_version

      @checked_cpflow_version = true

      result = ::Shell.cmd("gem", "search", "^cpflow$", "--remote", capture_stderr: true)
      return unless result[:success]

      matches = result[:output].match(/cpflow \((.+)\)/)
      return unless matches

      version = Cpflow::VERSION
      latest_version = matches[1]
      return unless Gem::Version.new(version) < Gem::Version.new(latest_version)

      ::Shell.warn("You are not using the latest 'cpflow' version. Please update it with 'gem update cpflow'.")
      $stderr.puts
    end

    # This is so that we're able to run `cpflow COMMAND --help` to print the help
    # (it basically changes it to `cpflow --help COMMAND`, which Thor recognizes)
    # Based on https://stackoverflow.com/questions/49042591/how-to-add-help-h-flag-to-thor-command
    def self.fix_help_option
      help_mappings = Thor::HELP_MAPPINGS + ["help"]
      matches = help_mappings & ARGV

      # Help option works correctly for subcommands
      return if matches && subcommand?

      matches.each do |match|
        ARGV.delete(match)
        ARGV.unshift(match)
      end
    end

    def self.subcommand?
      (subcommand_names & ARGV).any?
    end
    private_class_method :subcommand?

    # Needed to silence deprecation warning
    def self.exit_on_failure?
      true
    end

    # Needed to be able to use "run" as a command
    def self.is_thor_reserved_word?(word, type) # rubocop:disable Naming/PredicateName
      return false if word == "run"

      super
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

    def self.subcommand_names
      Dir["#{__dir__}/command/*"].filter_map { |name| File.basename(name) if File.directory?(name) }
    end

    def self.process_option_params(params)
      # Ensures that if no value is provided for a non-boolean option (e.g., `cpflow command --option`),
      # it defaults to an empty string instead of the option name (which is the default Thor behavior)
      params[:lazy_default] ||= "" if params[:type] != :boolean

      params
    end

    def self.klass_for(subcommand_name)
      klass_name = subcommand_name.to_s.split("-").map(&:capitalize).join
      full_klass_name = "Cpflow::#{klass_name}"
      return const_get(full_klass_name) if const_defined?(full_klass_name)

      Cpflow.const_set(klass_name, Class.new(BaseSubCommand)).tap do |subcommand_klass|
        desc(subcommand_name, "#{subcommand_name.capitalize} commands")
        subcommand(subcommand_name, subcommand_klass)
      end
    end
    private_class_method :klass_for

    @commands_with_required_options = []
    @commands_with_extra_options = []
    cli_package_name = @package_name

    ::Command::Base.common_options.each do |option|
      params = process_option_params(option[:params])
      class_option(option[:name], **params)
    end

    all_base_commands.each do |command_key, command_class| # rubocop:disable Metrics/BlockLength
      deprecated = deprecated_commands[command_key]

      name = command_class::NAME
      subcommand_name = command_class::SUBCOMMAND_NAME
      name_for_method = deprecated ? command_key : name.tr("-", "_")
      usage = command_class::USAGE.empty? ? name : command_class::USAGE
      requires_args = command_class::REQUIRES_ARGS
      default_args = command_class::DEFAULT_ARGS
      command_options = command_class::OPTIONS
      accepts_extra_options = command_class::ACCEPTS_EXTRA_OPTIONS
      description = command_class::DESCRIPTION
      long_description = command_class::LONG_DESCRIPTION
      examples = command_class::EXAMPLES
      hide = command_class::HIDE || deprecated
      with_info_header = command_class::WITH_INFO_HEADER
      validations = command_class::VALIDATIONS

      long_description += "\n#{examples}" if examples.length.positive?

      # `handle_argument_error` does not exist in the context below,
      # so we store it here to be able to use it
      raise_args_error = ->(*args) { handle_argument_error(commands[name_for_method], ArgumentError, *args) }

      # We'll handle required options manually in `Config`
      required_options = command_options.select { |option| option[:params][:required] }.map { |option| option[:name] }
      @commands_with_required_options.push(name_for_method.to_sym) if required_options.any?

      @commands_with_extra_options.push(name_for_method.to_sym) if accepts_extra_options

      klass = subcommand_name ? klass_for(subcommand_name) : self

      klass.class_eval do
        package_name(cli_package_name) if subcommand_name
        desc(usage, description, hide: hide)
        long_desc(long_description)

        command_options.each do |option|
          params = Cpflow::Cli.process_option_params(option[:params])
          method_option(option[:name], **params)
        end
      end

      klass.define_method(name_for_method) do |*provided_args| # rubocop:disable Metrics/BlockLength, Metrics/MethodLength
        if deprecated
          normalized_old_name = ::Helpers.normalize_command_name(command_key)
          ::Shell.warn_deprecated("Command '#{normalized_old_name}' is deprecated, " \
                                  "please use '#{name}' instead.")
          $stderr.puts
        end

        args = if provided_args.length.positive?
                 provided_args
               else
                 default_args
               end

        if (args.empty? && requires_args) || (!args.empty? && !requires_args && !accepts_extra_options)
          raise_args_error.call(args, nil)
        end

        begin
          Cpflow::Cli.validate_options!(options)

          config = Config.new(args, options, required_options)

          Cpflow::Cli.show_info_header(config) if with_info_header

          command = command_class.new(config)

          if validations.any? && ENV.fetch("DISABLE_VALIDATIONS", nil) != "true"
            doctor = DoctorService.new(command)
            doctor.run_validations(validations, silent_if_passing: true)
          end

          command.call
        rescue RuntimeError => e
          ::Shell.abort(e.message)
        end
      end
    rescue StandardError => e
      ::Shell.abort("Unable to load command: #{e.message}")
    end

    disable_required_check!(*@commands_with_required_options)
    check_unknown_options!(except: @commands_with_extra_options)
    stop_on_unknown_option!

    def self.validate_options!(options) # rubocop:disable Metrics/MethodLength
      options.each do |name, value|
        normalized_name = ::Helpers.normalize_option_name(name)
        raise "No value provided for option #{normalized_name}." if value.to_s.strip.empty?

        option = ::Command::Base.all_options.find { |current_option| current_option[:name].to_s == name }
        if option[:new_name]
          normalized_new_name = ::Helpers.normalize_option_name(option[:new_name])
          ::Shell.warn_deprecated("Option #{normalized_name} is deprecated, " \
                                  "please use #{normalized_new_name} instead.")
          $stderr.puts
        end

        params = option[:params]
        next unless params[:valid_regex]

        raise "Invalid value provided for option #{normalized_name}." unless value.match?(params[:valid_regex])
      end
    end

    def self.show_info_header(config) # rubocop:disable Metrics/MethodLength
      return if @showed_info_header

      rows = {}
      rows["ORG"] = config.org || "NOT PROVIDED!"
      rows["ORG"] += " (comes from CPLN_ORG env var)" if config.org_comes_from_env
      rows["APP"] = config.app || "NOT PROVIDED!"
      rows["APP"] += " (comes from CPLN_APP env var)" if config.app_comes_from_env

      rows.each do |key, value|
        puts "#{key}: #{value}"
      end

      @showed_info_header = true

      # Add a newline after the info header
      puts
    end
  end
end

Shell.trap_interrupt unless ENV.fetch("DISABLE_INTERRUPT_TRAP", nil) == "true"
