# frozen_string_literal: true

require "shellwords"

module Command
  class Run < Base
    def call
      clone_workload
      wait_for_replica
      connect_to_replica
    ensure
      delete_workload
    end

    private

    def clone_workload
      progress.puts "- Cloning workload '#{workload}' on '#{config.options[:app]}'"

      # Create a base copy of workload props
      old_data = cp.get_workload(workload)
      new_data = { "kind" => "workload", "name" => one_off, "spec" => old_data.fetch("spec") }
      container_data = new_data["spec"]["containers"].detect { _1["name"] == workload }

      # Stub workload command with dummy server that just responds to port
      # Needed to avoid execution of ENDTRYPOINT and CMD of Dockerfile
      port = container_data["ports"][0]["number"]
      container_data["command"] = "nc"
      container_data["args"] = ["-k", "-l", port]

      # Pass actual command to runner script via ENV
      workload_data["env"] << { "name" => "CONTROLPLANE_RUNNER", "value" => config.args.shelljoin } if runner

      # Create workload clone
      cp.apply(new_data)
    end

    def wait_for_replica
      progress.print "- Waiting for replica"
      until cp.get_replicas(one_off, location: location)&.dig("items", 0)
        progress.print "."
        sleep(1)
      end
      progress.puts
    end

    def connect_to_replica
      progress.puts "- Connecting"
      cp.connect_workload(one_off, location: location, runner: runner)
    end

    # TODO: add check if workload exists
    def delete_workload
      progress.puts "- Deleting workload"
      cp.delete_workload(one_off)
    end

    def cp
      @cp ||= Controlplane.new(config, org: config.one_off.fetch(:org))
    end

    def workload
      config.one_off[:workload]
    end

    def location
      config.one_off[:location]
    end

    def one_off
      @one_off ||= workload + Time.now.to_i.to_s
    end

    def runner
      "/app/runner.sh" if config.args.any?
    end
  end
end
