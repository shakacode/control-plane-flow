# frozen_string_literal: true

module Command
  class Run < Base
    def call
      clone_workload
      wait_for_replica
      run_in_replica
    ensure
      delete_workload
    end

    private

    def clone_workload
      progress.puts "- Cloning workload '#{workload}' on '#{config.options[:app]}'"

      # Create a base copy of workload props
      old_data = cp.workload_get(workload)
      new_data = { "kind" => "workload", "name" => one_off, "spec" => old_data.fetch("spec") }
      container_data = new_data["spec"]["containers"].detect { _1["name"] == workload }

      # Stub workload command with dummy server that just responds to port
      # Needed to avoid execution of ENDTRYPOINT and CMD of Dockerfile
      port = container_data["ports"][0]["number"]
      container_data["command"] = "nc"
      container_data["args"] = ["-k", "-l", port.to_s]

      # Ensure one-off workload will be running
      new_data["spec"]["defaultOptions"]["suspend"] = false

      # Create workload clone
      cp.apply(new_data)
    end

    def wait_for_replica
      progress.print "- Waiting for replica"
      until cp.workload_get_replicas(one_off, location: location)&.dig("items", 0)
        progress.print "."
        sleep(1)
      end
      progress.puts
    end

    def run_in_replica
      progress.puts "- Connecting"

      if config.args.empty?
        cp.workload_connect(one_off, location: location, container: workload)
      else
        cp.workload_exec(one_off, location: location, container: workload, command: config.args.shelljoin)
      end
    end

    # TODO: add check if workload exists
    def delete_workload
      progress.puts "- Deleting workload"
      cp.workload_delete(one_off)
    end

    def workload
      config[:one_off_workload]
    end

    def location
      config[:location]
    end

    def one_off
      @one_off ||= "#{workload}-run#{rand(1000..9999)}"
    end
  end
end
