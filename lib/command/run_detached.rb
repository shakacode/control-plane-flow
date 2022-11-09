# frozen_string_literal: true

module Command
  class RunDetached < Base
    def call
      clone_workload
      wait_for("workload to start") { cp.workload_get(one_off) }
      wait_for("workload to finish") { !cp.workload_get(one_off) }
      show_logs
    end

    private

    def clone_workload
      progress.puts "- Cloning workload '#{workload}' on '#{config.options[:app]}' to '#{one_off}'"

      # Create a base copy of workload props
      old_data = cp.workload_get(workload)
      new_data = { "kind" => "workload", "name" => one_off, "spec" => old_data.fetch("spec") }
      container_data = new_data["spec"]["containers"].detect { _1["name"] == workload }

      container_data["command"] = "/app/entrypoint.sh"
      container_data["args"] = []

      # Ensure one-off workload will be running
      new_data["spec"]["defaultOptions"]["suspend"] = false

      container_data["env"] << { "name" => "CONTROLPLANE_TOKEN", "value" => ControlplaneApiDirect.new.api_token }
      container_data["env"] << { "name" => "CONTROLPLANE_RUNNER", "value" => runner_script }

      # Create workload clone
      cp.apply(new_data)
    end

    def runner_script
      <<~SHELL
        nc -k -l $PORT &
        eval "#{args_join(config.args)}"
        curl ${CPLN_ENDPOINT}${CPLN_WORKLOAD} -H "Authorization: ${CONTROLPLANE_TOKEN}" -X DELETE -s
        while true; do sleep 1; done
      SHELL
    end

    def show_logs
      sleep(5) # to logs populate
      cmd =
        %(cpln logs '{gvc="#{cp.gvc}",workload="#{one_off}"}' --limit 200 --org #{cp.org} -o raw --direction backward)
      puts `#{cmd}`.split("\n").reverse.join("\n")
    end

    def workload
      config[:one_off_workload]
    end

    def one_off
      @one_off ||= "#{workload}-detached-#{rand(1000..9999)}"
    end
  end
end
