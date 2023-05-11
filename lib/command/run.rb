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
      use_local_token_option,
      terminal_size_option
    ].freeze
    DESCRIPTION = "Runs one-off **_interactive_** replicas (analog of `heroku run`)"
    LONG_DESCRIPTION = <<~DESC
      - Runs one-off **_interactive_** replicas (analog of `heroku run`)
      - Uses `Standard` workload type and `cpln exec` as the execution method, with CLI streaming
      - May not work correctly with tasks that last over 5 minutes (there's a Control Plane scaling bug at the moment)
      - If `fix_terminal_size` is `true` in the `.controlplane/controlplane.yml` file, the remote terminal size will be fixed to match the local terminal size (may also be overriden through `--terminal-size`)

      > **IMPORTANT:** Useful for development where it's needed for interaction, and where network connection drops and
      > task crashing are tolerable. For production tasks, it's better to use `cpl run:detached`.
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Opens shell (bash by default).
      cpl run -a $APP_NAME

      # Need to quote COMMAND if setting ENV value or passing args.
      cpl run 'LOG_LEVEL=warn rails db:migrate' -a $APP_NAME

      # COMMAND may also be passed at the end (in this case, no need to quote).
      cpl run -a $APP_NAME -- rails db:migrate

      # Runs command, displays output, and exits shell.
      cpl run ls / -a $APP_NAME
      cpl run rails db:migrate:status -a $APP_NAME

      # Runs command and keeps shell open.
      cpl run rails c -a $APP_NAME

      # Uses a different image (which may not be promoted yet).
      cpl run rails db:migrate -a $APP_NAME --image appimage:123 # Exact image name
      cpl run rails db:migrate -a $APP_NAME --image latest       # Latest sequential image

      # Uses a different workload than `one_off_workload` from `.controlplane/controlplane.yml`.
      cpl run bash -a $APP_NAME -w other-workload

      # Overrides remote CPLN_TOKEN env variable with local token.
      # Useful when superuser rights are needed in remote container.
      cpl run bash -a $APP_NAME --use-local-token
      ```
    EX

    attr_reader :location, :workload, :one_off, :container

    def call
      @location = config[:default_location]
      @workload = config.options["workload"] || config[:one_off_workload]
      @one_off = "#{workload}-run-#{rand(1000..9999)}"

      clone_workload
      wait_for_workload(one_off)
      wait_for_replica(one_off, location)
      run_in_replica
    ensure
      ensure_workload_deleted(one_off)
    end

    private

    def clone_workload # rubocop:disable Metrics/MethodLength
      progress.puts "- Cloning workload '#{workload}' on '#{config.options[:app]}' to '#{one_off}'"

      # Create a base copy of workload props
      spec = cp.fetch_workload!(workload).fetch("spec")
      container_spec = spec["containers"].detect { _1["name"] == workload } || spec["containers"].first
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
      image = "/org/#{config.org}/image/#{latest_image}" if image == "latest"
      container_spec["image"] = image if image

      # Set runner
      container_spec["env"] ||= []
      container_spec["env"] << { "name" => "CONTROLPLANE_RUNNER", "value" => runner_script }

      if config.options["use_local_token"]
        container_spec["env"] << { "name" => "CONTROLPLANE_TOKEN", "value" => ControlplaneApiDirect.new.api_token }
      end

      # Create workload clone
      cp.apply("kind" => "workload", "name" => one_off, "spec" => spec)
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
          rows, cols = `stty size`.split(/\s+/)
        end
        script += "stty rows #{rows}\nstty cols #{cols}\n" if rows && cols
      end

      script += args_join(config.args)
      script
    end

    def run_in_replica
      progress.puts "- Connecting"
      command = %(bash -c 'eval "$CONTROLPLANE_RUNNER"')
      cp.workload_exec(one_off, location: location, container: container, command: command)
    end
  end
end
