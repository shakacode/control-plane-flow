# frozen_string_literal: true

require_relative "../core/helpers"

module Command
  class Base # rubocop:disable Metrics/ClassLength
    attr_reader :config

    include Helpers

    VALIDATIONS_WITHOUT_ADDITIONAL_OPTIONS = %w[config].freeze
    VALIDATIONS_WITH_ADDITIONAL_OPTIONS = %w[templates].freeze
    ALL_VALIDATIONS = VALIDATIONS_WITHOUT_ADDITIONAL_OPTIONS + VALIDATIONS_WITH_ADDITIONAL_OPTIONS

    # Used to call the command (`cpflow SUBCOMMAND_NAME NAME`)
    SUBCOMMAND_NAME = nil
    # Used to call the command (`cpflow NAME`)
    # NAME = ""
    # Displayed when running `cpflow help` or `cpflow help NAME` (defaults to `NAME`)
    USAGE = ""
    # Throws error if `true` and no arguments are passed to the command
    # or if `false` and arguments are passed to the command
    REQUIRES_ARGS = false
    # Default arguments if none are passed to the command
    DEFAULT_ARGS = [].freeze
    # Options for the command (use option methods below)
    OPTIONS = [].freeze
    # Does not throw error if `true` and extra options
    # that are not specified in `OPTIONS` are passed to the command
    ACCEPTS_EXTRA_OPTIONS = false
    # Displayed when running `cpflow help`
    # DESCRIPTION = ""
    # Displayed when running `cpflow help NAME`
    # LONG_DESCRIPTION = ""
    # Displayed along with `LONG_DESCRIPTION` when running `cpflow help NAME`
    EXAMPLES = ""
    # If `true`, hides the command from `cpflow help`
    HIDE = false
    # Whether or not to show key information like ORG and APP name in commands
    WITH_INFO_HEADER = true
    # Which validations to run before the command
    VALIDATIONS = %w[config].freeze

    def initialize(config)
      @config = config
    end

    def self.all_commands # rubocop:disable Metrics/MethodLength
      Dir["#{__dir__}/**/*.rb"].each_with_object({}) do |file, result|
        content = File.read(file)

        classname = content.match(/^\s+class (?!Base\b)(\w+) < (?:.*(?!Command::)Base)(?:$| .*$)/)&.captures&.first
        next unless classname

        namespaces = content.scan(/^\s+module (\w+)/).flatten
        full_classname = [*namespaces, classname].join("::").prepend("::")

        command_key = File.basename(file, ".rb")
        prefix = namespaces[1..].map(&:downcase).join("_")
        command_key.prepend(prefix.concat("_")) unless prefix.empty?

        result[command_key.to_sym] = Object.const_get(full_classname)
      end
    end

    def self.common_options
      [org_option, verbose_option, trace_option]
    end

    # rubocop:disable Metrics/MethodLength
    def self.org_option(required: false)
      {
        name: :org,
        params: {
          aliases: ["-o"],
          banner: "ORG_NAME",
          desc: "Organization name",
          type: :string,
          required: required
        }
      }
    end

    def self.app_option(required: false)
      {
        name: :app,
        params: {
          aliases: ["-a"],
          banner: "APP_NAME",
          desc: "Application name",
          type: :string,
          required: required
        }
      }
    end

    def self.workload_option(required: false)
      {
        name: :workload,
        params: {
          aliases: ["-w"],
          banner: "WORKLOAD_NAME",
          desc: "Workload name",
          type: :string,
          required: required
        }
      }
    end

    def self.replica_option(required: false)
      {
        name: :replica,
        params: {
          aliases: ["-r"],
          banner: "REPLICA_NAME",
          desc: "Replica name",
          type: :string,
          required: required
        }
      }
    end

    def self.image_option(required: false)
      {
        name: :image,
        params: {
          aliases: ["-i"],
          banner: "IMAGE_NAME",
          desc: "Image name",
          type: :string,
          required: required
        }
      }
    end

    def self.log_method_option(required: false)
      {
        name: :log_method,
        params: {
          type: :numeric,
          banner: "LOG_METHOD",
          desc: "Log method",
          required: required,
          valid_values: [1, 2, 3],
          default: 3
        }
      }
    end

    def self.commit_option(required: false)
      {
        name: :commit,
        params: {
          aliases: ["-c"],
          banner: "COMMIT_HASH",
          desc: "Commit hash",
          type: :string,
          required: required
        }
      }
    end

    def self.location_option(required: false)
      {
        name: :location,
        params: {
          aliases: ["-l"],
          banner: "LOCATION_NAME",
          desc: "Location name",
          type: :string,
          required: required
        }
      }
    end

    def self.domain_option(required: false)
      {
        name: :domain,
        params: {
          banner: "DOMAIN_NAME",
          desc: "Domain name",
          type: :string,
          required: required
        }
      }
    end

    def self.upstream_token_option(required: false)
      {
        name: :upstream_token,
        params: {
          aliases: ["-t"],
          banner: "UPSTREAM_TOKEN",
          desc: "Upstream token",
          type: :string,
          required: required
        }
      }
    end

    def self.skip_confirm_option(required: false)
      {
        name: :yes,
        params: {
          aliases: ["-y"],
          banner: "SKIP_CONFIRM",
          desc: "Skip confirmation",
          type: :boolean,
          required: required
        }
      }
    end

    def self.version_option(required: false)
      {
        name: :version,
        params: {
          aliases: ["-v"],
          banner: "VERSION",
          desc: "Displays the current version of the CLI",
          type: :boolean,
          required: required
        }
      }
    end

    def self.use_local_token_option(required: false)
      {
        name: :use_local_token,
        params: {
          desc: "Override remote CPLN_TOKEN with local token",
          type: :boolean,
          required: required
        }
      }
    end

    def self.terminal_size_option(required: false)
      {
        name: :terminal_size,
        params: {
          banner: "ROWS,COLS",
          desc: "Override remote terminal size (e.g. `--terminal-size 10,20`)",
          type: :string,
          required: required,
          valid_regex: /^\d+,\d+$/
        }
      }
    end

    def self.wait_option(title = "", required: false)
      {
        name: :wait,
        params: {
          desc: "Waits for #{title}",
          type: :boolean,
          required: required
        }
      }
    end

    def self.verbose_option(required: false)
      {
        name: :verbose,
        params: {
          aliases: ["-d"],
          desc: "Shows detailed logs",
          type: :boolean,
          required: required
        }
      }
    end

    def self.trace_option(required: false)
      {
        name: :trace,
        params: {
          desc: "Shows trace of API calls. WARNING: may contain sensitive data",
          type: :boolean,
          required: required
        }
      }
    end

    def self.skip_secret_access_binding_option(required: false)
      {
        name: :skip_secret_access_binding,
        new_name: :skip_secrets_setup,
        params: {
          desc: "Skips secret access binding",
          type: :boolean,
          required: required
        }
      }
    end

    def self.skip_secrets_setup_option(required: false)
      {
        name: :skip_secrets_setup,
        params: {
          desc: "Skips secrets setup",
          type: :boolean,
          required: required
        }
      }
    end

    def self.run_release_phase_option(required: false)
      {
        name: :run_release_phase,
        params: {
          desc: "Runs release phase",
          type: :boolean,
          required: required
        }
      }
    end

    def self.logs_limit_option(required: false)
      {
        name: :limit,
        params: {
          banner: "NUMBER",
          desc: "Limit on number of log entries to show",
          type: :numeric,
          required: required,
          default: 200
        }
      }
    end

    def self.logs_since_option(required: false)
      {
        name: :since,
        params: {
          banner: "DURATION",
          desc: "Loopback window for showing logs " \
                "(see https://www.npmjs.com/package/parse-duration for the accepted formats, e.g., '1h')",
          type: :string,
          required: required,
          default: "1h"
        }
      }
    end

    def self.interactive_option(required: false)
      {
        name: :interactive,
        params: {
          desc: "Runs interactive command",
          type: :boolean,
          required: required
        }
      }
    end

    def self.detached_option(required: false)
      {
        name: :detached,
        params: {
          desc: "Runs non-interactive command, detaches, and prints commands to log and stop the job",
          type: :boolean,
          required: required
        }
      }
    end

    def self.cpu_option(required: false)
      {
        name: :cpu,
        params: {
          banner: "CPU",
          desc: "Overrides CPU millicores " \
                "(e.g., '100m' for 100 millicores, '1' for 1 core)",
          type: :string,
          required: required,
          valid_regex: /^\d+m?$/
        }
      }
    end

    def self.memory_option(required: false)
      {
        name: :memory,
        params: {
          banner: "MEMORY",
          desc: "Overrides memory size " \
                "(e.g., '100Mi' for 100 mebibytes, '1Gi' for 1 gibibyte)",
          type: :string,
          required: required,
          valid_regex: /^\d+[MG]i$/
        }
      }
    end

    def self.entrypoint_option(required: false)
      {
        name: :entrypoint,
        params: {
          banner: "ENTRYPOINT",
          desc: "Overrides entrypoint " \
                "(must be a single command or a script path that exists in the container)",
          type: :string,
          required: required,
          valid_regex: /^\S+$/
        }
      }
    end

    def self.validations_option(required: false)
      {
        name: :validations,
        params: {
          banner: "VALIDATION_1,VALIDATION_2,...",
          desc: "Which validations to run " \
                "(must be separated by a comma)",
          type: :string,
          required: required,
          default: VALIDATIONS_WITHOUT_ADDITIONAL_OPTIONS.join(","),
          valid_regex: /^(#{ALL_VALIDATIONS.join('|')})(,(#{ALL_VALIDATIONS.join('|')}))*$/
        }
      }
    end

    def self.skip_post_creation_hook_option(required: false)
      {
        name: :skip_post_creation_hook,
        params: {
          desc: "Skips post-creation hook",
          type: :boolean,
          required: required
        }
      }
    end

    def self.skip_pre_deletion_hook_option(required: false)
      {
        name: :skip_pre_deletion_hook,
        params: {
          desc: "Skips pre-deletion hook",
          type: :boolean,
          required: required
        }
      }
    end

    def self.add_app_identity_option(required: false)
      {
        name: :add_app_identity,
        params: {
          desc: "Adds app identity template if it does not exist",
          type: :boolean,
          required: required
        }
      }
    end

    def self.docker_context_option
      {
        name: :docker_context,
        params: {
          desc: "Path to the docker build context directory",
          type: :string,
          required: false
        }
      }
    end

    def self.dir_option(required: false)
      {
        name: :dir,
        params: {
          banner: "DIR",
          desc: "Output directory",
          type: :string,
          required: required
        }
      }
    end
    # rubocop:enable Metrics/MethodLength

    def self.all_options
      methods.grep(/_option$/).map { |method| send(method.to_s) }
    end

    def self.all_options_by_key_name
      all_options.each_with_object({}) do |option, result|
        option[:params][:aliases]&.each { |current_alias| result[current_alias.to_s] = option }
        result["--#{option[:name]}"] = option
      end
    end

    # NOTE: use simplified variant atm, as shelljoin do different escaping
    # TODO: most probably need better logic for escaping various quotes
    def args_join(args)
      args.join(" ")
    end

    def progress
      $stderr
    end

    def step_finish(success, abort_on_error: true)
      if success
        progress.puts(" #{Shell.color('done!', :green)}")
      else
        progress.puts(" #{Shell.color('failed!', :red)}\n\n#{Shell.read_from_tmp_stderr}\n\n")
        exit(ExitCode::ERROR_DEFAULT) if abort_on_error
      end
    end

    def step(message, abort_on_error: true, retry_on_failure: false, max_retry_count: 1000, wait: 1, &block) # rubocop:disable Metrics/MethodLength
      progress.print("#{message}...")

      Shell.use_tmp_stderr do
        success = false

        begin
          success =
            if retry_on_failure
              with_retry(max_retry_count: max_retry_count, wait: wait, &block)
            else
              yield
            end
        rescue RuntimeError => e
          Shell.write_to_tmp_stderr(e.message)
        end

        step_finish(success, abort_on_error: abort_on_error)
      end
    end

    def with_retry(max_retry_count:, wait:)
      retry_count = 0
      success = false

      while !success && retry_count <= max_retry_count
        success = yield
        break if success

        progress.print(".")
        Kernel.sleep(wait)
        retry_count += 1
      end

      success
    end

    def cp
      @cp ||= Controlplane.new(config)
    end

    def ensure_docker_running!
      result = Shell.cmd("docker", "version", capture_stderr: true)
      return if result[:success]

      raise "Can't run Docker. Please make sure that it's installed and started, then try again."
    end

    def run_command_in_latest_image(command, title:)
      # Need to prefix the command with '.controlplane/'
      # if it's a file in the '.controlplane' directory,
      # for backwards compatibility
      path = Pathname.new("#{config.app_cpln_dir}/#{command}").expand_path
      command = ".controlplane/#{command}" if File.exist?(path)

      progress.puts("Running #{title}...\n\n")

      begin
        run_cpflow_command("run", "-a", config.app, "--image", "latest", "--", command)
      rescue SystemExit => e
        progress.puts

        raise "Failed to run #{title}." if e.status.nonzero?

        progress.puts("Finished running #{title}.\n\n")
      end
    end

    def run_cpflow_command(command, *args)
      common_args = []

      self.class.common_options.each do |option|
        value = config.options[option[:name]]
        next if value.nil?

        name = "--#{option[:name].to_s.tr('_', '-')}"
        common_args.push(name, value)
      end

      Cpflow::Cli.start([command, *common_args, *args])
    end
  end
end
