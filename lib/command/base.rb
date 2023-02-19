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

    def self.all_options
      methods.grep(/_option$/).map { |method| send(method.to_s) }
    end

    def self.all_options_key_name
      all_options.each_with_object({}) do |option, result|
        option[:params][:aliases].each { |current_alias| result[current_alias.to_s] = option[:name] }
        result["--#{option[:name]}"] = option[:name]
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
      wait_for("workload to start") { cp.workload_get(workload) }
    end

    def wait_for_replica(workload, location)
      wait_for("replica") do
        cp.workload_get_replicas(workload, location: location)&.dig("items", 0)
      end
    end

    def ensure_workload_deleted(workload)
      progress.puts "- Ensure workload is deleted"
      cp.workload_delete(workload, no_raise: true)
    end

    def latest_image # rubocop:disable Metrics/MethodLength
      @latest_image ||=
        begin
          items = cp.image_query["items"]
          matching_items = items.filter_map do |item|
            item["name"] if item["name"].start_with?("#{config.app}:")
          end

          # Or special string to indicate no image available
          if matching_items.empty?
            "#{config.app}:#{NO_IMAGE_AVAILABLE}"
          else
            matching_items.max_by { |item| extract_image_number(item) }
          end
        end
    end

    def latest_image_next
      @latest_image_next ||= begin
        image = latest_image.split(":").first
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

    def cp
      @cp ||= Controlplane.new(config)
    end

    private

    # returns 0 if no prior image
    def extract_image_number(image_name)
      return 0 if image_name.end_with?(NO_IMAGE_AVAILABLE)

      image_name.match(/:(\d+)/)&.captures&.first.to_i
    end
  end
end
