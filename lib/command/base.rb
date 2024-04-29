# frozen_string_literal: true

require_relative "../core/helpers"

module Command
  class Base # rubocop:disable Metrics/ClassLength
    attr_reader :config

    include Helpers

    # Used to call the command (`cpl NAME`)
    # NAME = ""
    # Displayed when running `cpl help` or `cpl help NAME` (defaults to `NAME`)
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
    # Displayed when running `cpl help`
    # DESCRIPTION = ""
    # Displayed when running `cpl help NAME`
    # LONG_DESCRIPTION = ""
    # Displayed along with `LONG_DESCRIPTION` when running `cpl help NAME`
    EXAMPLES = ""
    # If `true`, hides the command from `cpl help`
    HIDE = false
    # Whether or not to show key information like ORG and APP name in commands
    WITH_INFO_HEADER = true

    NO_IMAGE_AVAILABLE = "NO_IMAGE_AVAILABLE"

    def initialize(config)
      @config = config
    end

    def self.all_commands
      Dir["#{__dir__}/*.rb"].each_with_object({}) do |file, result|
        filename = File.basename(file, ".rb")
        classname = File.read(file).match(/^\s+class (\w+) < Base($| .*$)/)&.captures&.first
        result[filename.to_sym] = Object.const_get("::Command::#{classname}") if classname
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
          required: required
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

    def self.clean_on_failure_option(required: false)
      {
        name: :clean_on_failure,
        params: {
          desc: "Deletes workload when finished with failure (success always deletes)",
          type: :boolean,
          required: required,
          default: true
        }
      }
    end

    def self.skip_secret_access_binding_option(required: false)
      {
        name: :skip_secret_access_binding,
        params: {
          desc: "Skips secret access binding",
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

    def wait_for_workload(workload)
      step("Waiting for workload", retry_on_failure: true) do
        cp.fetch_workload(workload)
      end
    end

    def wait_for_replica(workload, location)
      step("Waiting for replica", retry_on_failure: true) do
        cp.workload_get_replicas_safely(workload, location: location)&.dig("items", 0)
      end
    end

    def ensure_workload_deleted(workload)
      step("Deleting workload") do
        cp.delete_workload(workload)
      end
    end

    def latest_image_from(items, app_name: config.app, name_only: true)
      matching_items = items.select { |item| item["name"].start_with?("#{app_name}:") }

      # Or special string to indicate no image available
      if matching_items.empty?
        name_only ? "#{app_name}:#{NO_IMAGE_AVAILABLE}" : nil
      else
        latest_item = matching_items.max_by { |item| extract_image_number(item["name"]) }
        name_only ? latest_item["name"] : latest_item
      end
    end

    def latest_image(app = config.app, org = config.org, refresh: false)
      @latest_image ||= {}
      @latest_image[app] = nil if refresh
      @latest_image[app] ||=
        begin
          items = cp.query_images(app, org)["items"]
          latest_image_from(items, app_name: app)
        end
    end

    def latest_image_next(app = config.app, org = config.org, commit: nil)
      # debugger
      commit ||= config.options[:commit]

      @latest_image_next ||= {}
      @latest_image_next[app] ||= begin
        latest_image_name = latest_image(app, org)
        image = latest_image_name.split(":").first
        image += ":#{extract_image_number(latest_image_name) + 1}"
        image += "_#{commit}" if commit
        image
      end
    end

    def extract_image_commit(image_name)
      image_name.match(/_(\h+)$/)&.captures&.first
    end

    # NOTE: use simplified variant atm, as shelljoin do different escaping
    # TODO: most probably need better logic for escaping various quotes
    def args_join(args)
      args.join(" ")
    end

    def progress
      $stderr
    end

    def step_error(error, abort_on_error: true)
      message = error.message
      if abort_on_error
        progress.puts(" #{Shell.color('failed!', :red)}\n\n")
        Shell.abort(message)
      else
        Shell.write_to_tmp_stderr(message)
      end
    end

    def step_finish(success)
      if success
        progress.puts(" #{Shell.color('done!', :green)}")
      else
        progress.puts(" #{Shell.color('failed!', :red)}\n\n#{Shell.read_from_tmp_stderr}\n\n")
      end
    end

    def step(message, abort_on_error: true, retry_on_failure: false) # rubocop:disable Metrics/MethodLength
      progress.print("#{message}...")

      Shell.use_tmp_stderr do
        success = false

        begin
          if retry_on_failure
            until (success = yield)
              progress.print(".")
              Kernel.sleep(1)
            end
          else
            success = yield
          end
        rescue RuntimeError => e
          step_error(e, abort_on_error: abort_on_error)
        end

        step_finish(success)
      end
    end

    def cp
      @cp ||= Controlplane.new(config)
    end

    def app_location_link
      "/org/#{config.org}/location/#{config.location}"
    end

    def app_image_link
      "/org/#{config.org}/image/#{latest_image}"
    end

    def app_identity
      "#{config.app}-identity"
    end

    def app_identity_link
      "/org/#{config.org}/gvc/#{config.app}/identity/#{app_identity}"
    end

    def app_secrets
      "#{config.app_prefix}-secrets"
    end

    def app_secrets_policy
      "#{app_secrets}-policy"
    end

    def ensure_docker_running!
      result = Shell.cmd("docker", "version", capture_stderr: true)
      return if result[:success]

      raise "Can't run Docker. Please make sure that it's installed and started, then try again."
    end

    private

    # returns 0 if no prior image
    def extract_image_number(image_name)
      return 0 if image_name.end_with?(NO_IMAGE_AVAILABLE)

      image_name.match(/:(\d+)/)&.captures&.first.to_i
    end
  end
end
