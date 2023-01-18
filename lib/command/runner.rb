# frozen_string_literal: true

module Command
  class Runner < Base
    WORKLOAD_SLEEP_CHECK = 2

    attr_reader :location, :workload, :one_off

    def call
      abort("ERROR: should specify a command to execute") if config.args.empty?

      @location = config[:location]
      @workload = config[:one_off_workload]
      @one_off = "#{workload}-runner-#{rand(1000..9999)}"

      clone_workload
      wait_for_workload(one_off)
      show_logs_waiting
    ensure
      ensure_workload_deleted(one_off)
      exit(1) if @crashed
    end

    private

    def clone_workload # rubocop:disable Metrics/MethodLength
      progress.puts "- Cloning workload '#{workload}' on '#{config.options[:app]}' to '#{one_off}'"

      # Get base specs of workload
      spec = cp.workload_get(workload).fetch("spec")
      container = spec["containers"].detect { _1["name"] == workload } || spec["containers"].first

      # remove other containers if any
      spec["containers"] = [container]

      # Set runner
      container["command"] = "bash"
      container["args"] = ["-c", 'eval "$CONTROLPLANE_RUNNER"']

      # Ensure one-off workload will be running
      spec["defaultOptions"]["suspend"] = false

      # Override image if specified
      image = config.options[:image]
      image = "/org/#{config[:org]}/image/#{latest_image}" if image == "latest"
      container["image"] = image if image

      # Set cron job props
      spec["type"] = "cron"
      spec["job"] = { "schedule" => "* * * * *", "restartPolicy" => "Never" }
      spec["defaultOptions"]["autoscaling"] = {}
      container.delete("ports")

      container["env"] ||= []
      container["env"] << { "name" => "CONTROLPLANE_TOKEN", "value" => ControlplaneApiDirect.new.api_token }
      container["env"] << { "name" => "CONTROLPLANE_RUNNER", "value" => runner_script }

      # Create workload clone
      cp.apply("kind" => "workload", "name" => one_off, "spec" => spec)
    end

    def runner_script
      script = "echo '-- STARTED RUNNER SCRIPT --'\n"
      script += Scripts.helpers_cleanup

      script += <<~SHELL
        if ! eval "#{args_join(config.args)}"; then echo "----- CRASHED -----"; fi

        echo "-- FINISHED RUNNER SCRIPT, DELETING WORKLOAD --"
        sleep 10 # grace time for logs propagation
        curl ${CPLN_ENDPOINT}${CPLN_WORKLOAD} -H "Authorization: ${CONTROLPLANE_TOKEN}" -X DELETE -s -o /dev/null
        while true; do sleep 1; done # wait for SIGTERM
      SHELL

      script
    end

    def show_logs_waiting # rubocop:disable Metrics/MethodLength
      progress.puts "- Scheduled, fetching logs (it is cron job, so it may take up to a minute to start)"
      begin
        while cp.workload_get(one_off)
          sleep(WORKLOAD_SLEEP_CHECK)
          print_uniq_logs
        end
      rescue RuntimeError => e
        progress.puts "ERROR: #{e}"
        retry
      end
      progress.puts "- Finished workload and logger"
    end

    def print_uniq_logs
      @printed_log_entries ||= []
      ts = Time.now.to_i
      entries = normalized_log_entries(from: ts - 60, to: ts)

      (entries - @printed_log_entries).sort.each do |(_ts, val)|
        @crashed = true if val.match?(/^----- CRASHED -----$/)
        puts val
      end

      @printed_log_entries = entries # as well truncate old entries if any
    end

    def normalized_log_entries(from:, to:)
      log = cp.log_get(workload: one_off, from: from, to: to)

      log["data"]["result"]
        .each_with_object([]) { |obj, result| result.concat(obj["values"]) }
        .select { |ts, _val| ts[..-10].to_i > from }
    end
  end
end
