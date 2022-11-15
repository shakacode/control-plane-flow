# frozen_string_literal: true

module Command
  class Run < Base
    attr_reader :location, :workload, :one_off

    def call
      abort("ERROR: should specify a command to execute") if config.args.empty?

      @location = config[:location]
      @workload = config[:one_off_workload]
      @one_off = "#{workload}-run-#{rand(1000..9999)}"

      clone_workload
      wait_for_workload(one_off)
      wait_for_replica(one_off, location)
      run_in_replica
    ensure
      ensure_workload_deleted(one_off)
    end

    private

    def clone_workload
      progress.puts "- Cloning workload '#{workload}' on '#{config.options[:app]}' to '#{one_off}'"

      # Create a base copy of workload props
      spec = cp.workload_get(workload).fetch("spec")
      container = spec["containers"].detect { _1["name"] == workload } || spec["containers"].first

      # Stub workload command with dummy server that just responds to port
      # Needed to avoid execution of ENTRYPOINT and CMD of Dockerfile
      container["command"] = "ruby"
      container["args"] = ["-e", Scripts.http_dummy_server_ruby]

      # Ensure one-off workload will be running
      spec["defaultOptions"]["suspend"] = false

      # Set runner
      container["env"] << { "name" => "CONTROLPLANE_RUNNER", "value" => runner_script }

      # Create workload clone
      cp.apply("kind" => "workload", "name" => one_off, "spec" => spec)
    end

    def runner_script
      script = Scripts.expand_common_env_secret
      script += Scripts.helpers_cleanup
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
