# frozen_string_literal: true

module Command
  class Base # rubocop:disable Metrics/ClassLength
    attr_reader :config

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
    # Displayed when running `cpl help`
    # DESCRIPTION = ""
    # Displayed when running `cpl help NAME`
    # LONG_DESCRIPTION = ""
    # Displayed along with `LONG_DESCRIPTION` when running `cpl help NAME`
    EXAMPLES = ""
    # If `true`, hides the command from `cpl help`
    HIDE = false

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

    def self.all_options
      methods.grep(/_option$/).map { |method| send(method.to_s) }
    end

    def self.all_options_by_key_name
      all_options.each_with_object({}) do |option, result|
        option[:params][:aliases]&.each { |current_alias| result[current_alias.to_s] = option }
        result["--#{option[:name]}"] = option
      end
    end

    def wait_for(title)
      progress.print "- Waiting for #{title}"
      until yield
        progress.print(".")
        sleep(1)
      end
      progress.puts
    end

    def wait_for_workload(workload)
      wait_for("workload to start") { cp.fetch_workload(workload) }
    end

    def wait_for_replica(workload, location)
      wait_for("replica") do
        cp.workload_get_replicas_safely(workload, location: location)&.dig("items", 0)
      end
    end

    def ensure_workload_deleted(workload)
      progress.puts "- Ensure workload is deleted"
      cp.delete_workload(workload)
    end

    def latest_image_from(items, app_name: config.app, name_only: true)
      matching_items = items.filter { |item| item["name"].start_with?("#{app_name}:") }

      # Or special string to indicate no image available
      if matching_items.empty?
        "#{app_name}:#{NO_IMAGE_AVAILABLE}"
      else
        latest_item = matching_items.max_by { |item| extract_image_number(item["name"]) }
        name_only ? latest_item["name"] : latest_item
      end
    end

    def latest_image(app = config.app, org = config.org)
      @latest_image ||= {}
      @latest_image[app] ||=
        begin
          items = cp.image_query(app, org)["items"]
          latest_image_from(items, app_name: app)
        end
    end

    def latest_image_next(app = config.app, org = config.org)
      @latest_image_next ||= {}
      @latest_image_next[app] ||= begin
        image = latest_image(app, org).split(":").first
        image += ":#{extract_image_number(latest_image) + 1}"
        image += "_#{config.options[:commit]}" if config.options[:commit]
        image
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

    def step(message, abort_on_error: true) # rubocop:disable Metrics/MethodLength
      progress.print("#{message}...")

      Shell.use_tmp_stderr do
        success = false

        begin
          success = yield
        rescue RuntimeError => e
          message = e.message
          if abort_on_error
            progress.puts(" #{Shell.color('failed!', :red)}\n\n")
            Shell.abort(message)
          else
            Shell.write_to_tmp_stderr(message)
          end
        end

        if success
          progress.puts(" #{Shell.color('done!', :green)}")
        else
          progress.puts(" #{Shell.color('failed!', :red)}\n\n#{Shell.read_from_tmp_stderr}\n\n")
        end
      end
    end

    def cp
      @cp ||= Controlplane.new(config)
    end

    def perform(cmd)
      system(cmd) || exit(false)
    end

    private

    # returns 0 if no prior image
    def extract_image_number(image_name)
      return 0 if image_name.end_with?(NO_IMAGE_AVAILABLE)

      image_name.match(/:(\d+)/)&.captures&.first.to_i
    end
  end
end
