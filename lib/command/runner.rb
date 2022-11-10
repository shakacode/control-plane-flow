# frozen_string_literal: true

module Command
  class Runner < Base
    def call
      clone_workload
      wait_for("workload to start") { cp.workload_get(one_off) }
      show_logs_waiting
    ensure
      delete_workload
    end

    private

    def clone_workload # rubocop:disable Metrics/MethodLength
      progress.puts "- Cloning workload '#{workload}' on '#{config.options[:app]}' to '#{one_off}'"

      # Get base specs of workload
      spec = cp.workload_get(workload).fetch("spec")
      container = spec["containers"].detect { _1["name"] == workload } || spec["containers"].first

      container["command"] = "bash"
      container["args"] = ["-c", 'eval "$CONTROLPLANE_RUNNER"']

      # Ensure one-off workload will be running
      spec["defaultOptions"]["suspend"] = false

      @type = :cron

      case @type
      when :standard
        spec["type"] = "standard"
        # spec["defaultOptions"]["autoscaling"] = { "metric" => "cpu", "target" => 100, "maxScale" => 1 }
        # spec["defaultOptions"]["autoscaling"] = { "metric" => "latency", "maxScale" => 1 }
        # container["cpu"] = "50m"
        # container["memory"] = "512Mi"
        # container["ports"][0]["protocol"] = "tcp"
        # spec["firewallConfig"]["external"]["inboundAllowCIDR"] = []
        # spec["firewallConfig"]["internal"] = { "inboundAllowType" => "same-gvc" }
      when :cron
        spec["type"] = "cron"
        spec["job"] = { "schedule" => "* * * * *", "restartPolicy" => "Never" }
        spec["defaultOptions"]["autoscaling"] = {}
        container.delete("ports")
      else
        raise("Unknown container type :#{type}")
      end

      container["env"] << { "name" => "CONTROLPLANE_TOKEN", "value" => ControlplaneApiDirect.new.api_token }
      container["env"] << { "name" => "CONTROLPLANE_RUNNER", "value" => runner_script }

      # Create workload clone
      cp.apply("kind" => "workload", "name" => one_off, "spec" => spec)
    end

    # NOTE: please escape all '/' as '//' (as it is ruby interpolation here as well)
    def runner_script # rubocop:disable Metrics/MethodLength
      script = <<~SHELL
        echo "-- START RUNNER SCRIPT --"
      SHELL

      script += <<~SHELL if @type == :standard
        REPLICAS_QTY=$( \
          curl ${CPLN_ENDPOINT}/org/shakacode-staging/gvc/#{config.app}/workload/#{one_off}/deployment/#{location} \
          -H "Authorization: ${CONTROLPLANE_TOKEN}" -s | grep -o '"replicas":[0-9]*' | grep -o '[0-9]*')

        if [ "$REPLICAS_QTY" -gt 0 ]; then
          echo "-- MULTIPLE REPLICAS ATTEMPT !!!! replicas: $REPLICAS_QTY"
          exit -1
        fi
      SHELL

      script += <<~SHELL if @type == :standard
        ruby -e 'require "socket"; s=TCPServer.new(ENV["PORT"]); loop do c=s.accept;c.puts("HTTP/1.1 200 OK\\nContent-Length: 2\\n\\nOk");c.close end' &
      SHELL

      script += <<~SHELL if @type == :disabled
        ruby -e 'require "net/http"; uri = URI(ENV["CPLN_GLOBAL_ENDPOINT"]); loop do puts Net::HTTP.get(uri); sleep(5); end' &
      SHELL

      script += <<~SHELL
        # expand common env from secret
        if [ -n "$CONTROLPLANE_COMMON_ENV" ]; then
          echo "$CONTROLPLANE_COMMON_ENV" |
            sed -e 's/^{"//' -e 's/"}$//' -e 's/","/\\n/g' |
            sed 's/\\(.*\\)":"\\(.*\\)/export \\1="${\\1:-\\2}"/g' > ~/.controlplane_common_env

          . ~/.controlplane_common_env
        fi

        if ! eval "#{args_join(config.args)}"; then
          echo "----- CRASHED -----"
        fi

        echo "-- FINISH RUNNER SCRIPT, DELETING WORKLOAD --"
        curl ${CPLN_ENDPOINT}${CPLN_WORKLOAD} -H "Authorization: ${CONTROLPLANE_TOKEN}" -X DELETE -s -o /dev/null
        while true; do sleep 1; done # wait for SIGTERM
      SHELL

      script
    end

    def show_logs_waiting # rubocop:disable Metrics/MethodLength
      progress.puts "- Started, connecting to logs"
      cmd = %(cpln logs '{gvc="#{cp.gvc}",workload="#{one_off}"}' --org #{cp.org} -o raw -t --since 10s)
      logger = Thread.new { system(cmd) }

      while cp.workload_get(one_off)
        sleep(2)
        next if logger.alive?

        progress.puts("Logger crashed, restarting logger...")
        logger = Thread.new { system(cmd) }
      end

      progress.puts "- Finished workload"
      sleep(2) # final wait for logs to catch up
      Thread.kill(logger)
      sleep(0.5) while logger.alive?
      $stdout.sync
      progress.puts "- Finished logger"
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

    def delete_workload
      progress.puts "- Ensure workload is deleted"
      cp.workload_delete(one_off)
    end
  end
end
