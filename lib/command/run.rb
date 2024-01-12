# frozen_string_literal: true

module Command
  class Run < Base
    NAME = "run"
    USAGE = "run COMMAND"
    REQUIRES_ARGS = true
    DEFAULT_ARGS = ["bash"].freeze
    OPTIONS = [
      app_option(required: true),
      image_option,
      workload_option,
      location_option,
      use_local_token_option,
      terminal_size_option
    ].freeze
    DESCRIPTION = "Runs one-off **_interactive_** replicas (analog of `heroku run`)"
    LONG_DESCRIPTION = <<~DESC
      - Runs one-off **_interactive_** replicas (analog of `heroku run`)
      - Uses `Standard` workload type and `cpln exec` as the execution method, with CLI streaming
      - If `fix_terminal_size` is `true` in the `.controlplane/controlplane.yml` file, the remote terminal size will be fixed to match the local terminal size (may also be overriden through `--terminal-size`)

      > **IMPORTANT:** Useful for development where it's needed for interaction, and where network connection drops and
      > task crashing are tolerable. For production tasks, it's better to use `cpl run:detached`.
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Opens shell (bash by default).
      cpl run -a $APP_NAME

      # Need to quote COMMAND if setting ENV value or passing args.
      cpl run -a $APP_NAME -- 'LOG_LEVEL=warn rails db:migrate'

      # Runs command, displays output, and exits shell.
      cpl run -a $APP_NAME -- ls /
      cpl run -a $APP_NAME -- rails db:migrate:status

      # Runs command and keeps shell open.
      cpl run -a $APP_NAME -- rails c

      # Uses a different image (which may not be promoted yet).
      cpl run -a $APP_NAME --image appimage:123 -- rails db:migrate # Exact image name
      cpl run -a $APP_NAME --image latest -- rails db:migrate       # Latest sequential image

      # Uses a different workload than `one_off_workload` from `.controlplane/controlplane.yml`.
      cpl run -a $APP_NAME -w other-workload -- bash

      # Overrides remote CPLN_TOKEN env variable with local token.
      # Useful when superuser rights are needed in remote container.
      cpl run -a $APP_NAME --use-local-token -- bash
      ```
    EX

    attr_reader :location, :workload_to_clone, :workload_clone, :container

    def call # rubocop:disable Metrics/MethodLength
      @location = config.location
      @workload_to_clone = config.options["workload"] || config[:one_off_workload]
      @workload_clone = "#{workload_to_clone}-run-#{random_four_digits}"

      step("Cloning workload '#{workload_to_clone}' on app '#{config.options[:app]}' to '#{workload_clone}'") do
        clone_workload
      end

      wait_for_workload(workload_clone)
      wait_for_replica(workload_clone, location)
      run_in_replica
    ensure
      progress.puts
      ensure_workload_deleted(workload_clone)
    end

    private

    def clone_workload # rubocop:disable Metrics/MethodLength
      # Create a base copy of workload props
      spec = cp.fetch_workload!(workload_to_clone).fetch("spec")
      container_spec = spec["containers"].detect { _1["name"] == workload_to_clone } || spec["containers"].first
      @container = container_spec["name"]

      # remove other containers if any
      spec["containers"] = [container_spec]

      # Stub workload command with dummy server that just responds to port
      # Needed to avoid execution of ENTRYPOINT and CMD of Dockerfile
      container_spec["command"] = "ruby"
      container_spec["args"] = ["-e", Scripts.http_dummy_server_ruby]

      # Ensure one-off workload will be running
      spec["defaultOptions"]["suspend"] = false

      # Ensure no scaling
      spec["defaultOptions"]["autoscaling"]["minScale"] = 1
      spec["defaultOptions"]["autoscaling"]["maxScale"] = 1
      spec["defaultOptions"]["capacityAI"] = false

      # Override image if specified
      image = config.options[:image]
      image = latest_image if image == "latest"
      container_spec["image"] = "/org/#{config.org}/image/#{image}" if image

      # Set runner
      container_spec["env"] ||= []
      container_spec["env"] << { "name" => "CONTROLPLANE_RUNNER", "value" => runner_script }

      if config.options["use_local_token"]
        container_spec["env"] << { "name" => "CONTROLPLANE_TOKEN",
                                   "value" => ControlplaneApiDirect.new.api_token[:token] }
      end

      # Create workload clone
      cp.apply_hash("kind" => "workload", "name" => workload_clone, "spec" => spec)
    end

    def runner_script # rubocop:disable Metrics/MethodLength
      script = Scripts.helpers_cleanup

      if config.options["use_local_token"]
        script += <<~SHELL
          CPLN_TOKEN=$CONTROLPLANE_TOKEN
          unset CONTROLPLANE_TOKEN
        SHELL
      end

      # NOTE: fixes terminal size to match local terminal
      if config.current[:fix_terminal_size] || config.options[:terminal_size]
        if config.options[:terminal_size]
          rows, cols = config.options[:terminal_size].split(",")
        else
          rows, cols = Shell.cmd("stty size")[:output].split(/\s+/)
        end
        script += "stty rows #{rows}\nstty cols #{cols}\n" if rows && cols
      end

      script += args_join(config.args)
      script
    end

    def run_in_replica
      progress.puts("Connecting...\n\n")
      command = %(bash -c 'eval "$CONTROLPLANE_RUNNER"')
      cp.workload_exec(workload_clone, location: location, container: container, command: command)
    end
  end
end
