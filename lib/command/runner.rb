# frozen_string_literal: true

module Command
  class Runner < Base
    def call
      clone_workload
      wait_for("workload to start") { cp.workload_get(one_off) }
      show_logs_waiting
    end

    private

    def clone_workload
      progress.puts "- Cloning workload '#{workload}' on '#{config.options[:app]}' to '#{one_off}'"

      # Create a base copy of workload props
      old_data = cp.workload_get(workload)
      new_data = { "kind" => "workload", "name" => one_off, "spec" => old_data.fetch("spec") }
      container_data = new_data["spec"]["containers"].detect { _1["name"] == workload }

      container_data["command"] = "bash"
      container_data["args"] = ["-c", 'eval "$CONTROLPLANE_RUNNER"']

      # Ensure one-off workload will be running
      new_data["spec"]["defaultOptions"]["suspend"] = false

      container_data["env"] << { "name" => "CONTROLPLANE_TOKEN", "value" => ControlplaneApiDirect.new.api_token }
      container_data["env"] << { "name" => "CONTROLPLANE_RUNNER", "value" => runner_script }

      # Create workload clone
      cp.apply(new_data)
    end

    # NOTE: please escape all '/' as '//' (as it is ruby interpolation here as well)
    def runner_script
      <<~SHELL
        # echo "-- START RUNNER SCRIPT --"

        # stub PORT with dummy listener (to avoid restarts)
        nc -k -l $PORT &

        # expand common env from secret
        echo "$CONTROLPLANE_COMMON_ENV" |
          sed -e 's/^{"//' -e 's/"}$//' -e 's/","/\\n/g' |
          sed 's/\\(.*\\)":"\\(.*\\)/export \\1="${\\1:-\\2}"/g' > ~/.controlplane_common_env
        . ~/.controlplane_common_env

        # HACK: quick-hack, remove
        export app_domain=${app_domain:-$CPLN_GLOBAL_ENDPOINT}

        eval "#{args_join(config.args)}"

        # echo "-- FINISH RUNNER SCRIPT --"

        sleep 5

        # kill self
        curl ${CPLN_ENDPOINT}${CPLN_WORKLOAD} -H "Authorization: ${CONTROLPLANE_TOKEN}" -X DELETE -s -o /dev/null
        # echo "-- FINISH DELETING, WAIT..."

        # wait for SIGTERM
        while true; do sleep 1; done

        # echo "-- FINISH WAIT"
      SHELL
    end

    def show_logs_waiting # rubocop:disable Metrics/MethodLength
      cmd = %(cpln logs '{gvc="#{cp.gvc}",workload="#{one_off}"}' --org #{cp.org} -o raw -t)
      logger = Thread.new { system(cmd) }

      while cp.workload_get(one_off)
        sleep(2)
        unless logger.status
          progress.puts("Logger crashed, restarting logger...")
          logger = Thread.new { system(cmd) }
        end
      end

      sleep(2) # final wait
      Thread.kill(logger)
      sleep(0.1) while logger.status
    end

    def one_off
      @one_off ||= "#{workload}-runner-#{rand(1000..9999)}"
    end

    def workload
      config[:one_off_workload]
    end

    def location
      config[:location]
    end
  end
end
