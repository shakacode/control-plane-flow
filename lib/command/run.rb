# frozen_string_literal: true

module Command
  class Run < Base
    NAME = "run"
    USAGE = "run COMMAND"
    REQUIRES_ARGS = true
    OPTIONS = [
      app_option(required: true),
      image_option
    ].freeze
    DESCRIPTION = "Runs one-off **_interactive_** replicas (analog of `heroku run`)"
    LONG_DESCRIPTION = <<~HEREDOC
      - Runs one-off **_interactive_** replicas (analog of `heroku run`)
      - Uses `Standard` workload type and `cpln exec` as the execution method, with CLI streaming
      - May not work correctly with tasks that last over 5 minutes (there's a Control Plane scaling bug at the moment)

      > **IMPORTANT:** Useful for development where it's needed for interaction, and where network connection drops and
      > task crashing are tolerable. For production tasks, it's better to use `cpl run:detached`.
    HEREDOC
    EXAMPLES = <<~HEREDOC
      ```sh
      # Opens shell (bash by default).
      cpl run -a $APP_NAME

      # Runs command, displays output, and exits shell.
      cpl run ls / -a $APP_NAME
      cpl run rails db:migrate:status -a $APP_NAME

      # Runs command and keeps shell open.
      cpl run rails c -a $APP_NAME

      # Uses a different image (which may not be promoted yet).
      cpl run rails db:migrate -a $APP_NAME --image appimage:123 # Exact image name
      cpl run rails db:migrate -a $APP_NAME --image latest       # Latest sequential image
      ```
    HEREDOC

    attr_reader :location, :workload, :one_off

    def call
      @location = config[:default_location]
      @workload = config[:one_off_workload]
      @one_off = "#{workload}-run-#{rand(1000..9999)}"

      clone_workload
      wait_for_workload(one_off)
      sleep 2 # sometimes replica query lags workload creation, despite ok by prev query
      wait_for_replica(one_off, location)
      run_in_replica
    ensure
      ensure_workload_deleted(one_off)
    end

    private

    def clone_workload # rubocop:disable Metrics/MethodLength
      progress.puts "- Cloning workload '#{workload}' on '#{config.options[:app]}' to '#{one_off}'"

      # Create a base copy of workload props
      spec = cp.workload_get(workload).fetch("spec")
      container = spec["containers"].detect { _1["name"] == workload } || spec["containers"].first

      # remove other containers if any
      spec["containers"] = [container]

      # Stub workload command with dummy server that just responds to port
      # Needed to avoid execution of ENTRYPOINT and CMD of Dockerfile
      container["command"] = "ruby"
      container["args"] = ["-e", Scripts.http_dummy_server_ruby]

      # Ensure one-off workload will be running
      spec["defaultOptions"]["suspend"] = false

      # Ensure no scaling
      spec["defaultOptions"]["autoscaling"]["minScale"] = 1
      spec["defaultOptions"]["autoscaling"]["minScale"] = 1
      spec["defaultOptions"]["capacityAI"] = false

      # Override image if specified
      image = config.options[:image]
      image = "/org/#{config[:cpln_org]}/image/#{latest_image}" if image == "latest"
      container["image"] = image if image

      # Set runner
      container["env"] ||= []
      container["env"] << { "name" => "CONTROLPLANE_RUNNER", "value" => runner_script }

      # Create workload clone
      cp.apply("kind" => "workload", "name" => one_off, "spec" => spec)
    end

    def runner_script
      script = Scripts.helpers_cleanup
      script += args_join(config.args)
      script
    end

    def run_in_replica
      progress.puts "- Connecting"
      command = %(bash -c 'eval "$CONTROLPLANE_RUNNER"')
      cp.workload_exec(one_off, location: location, container: workload, command: command)
    end
  end
end
