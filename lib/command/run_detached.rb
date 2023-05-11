# frozen_string_literal: true

module Command
  class RunDetached < Base # rubocop:disable Metrics/ClassLength
    NAME = "run:detached"
    USAGE = "run:detached COMMAND"
    REQUIRES_ARGS = true
    OPTIONS = [
      app_option(required: true),
      image_option,
      workload_option
    ].freeze
    DESCRIPTION = "Runs one-off **_non-interactive_** replicas (close analog of `heroku run:detached`)"
    LONG_DESCRIPTION = <<~DESC
      - Runs one-off **_non-interactive_** replicas (close analog of `heroku run:detached`)
      - Uses `Cron` workload type with log async fetching
      - Implemented with only async execution methods, more suitable for production tasks
      - Has alternative log fetch implementation with only JSON-polling and no WebSockets
      - Less responsive but more stable, useful for CI tasks
    DESC
    EXAMPLES = <<~EX
      ```sh
      cpl run:detached rails db:prepare -a $APP_NAME

      # Need to quote COMMAND if setting ENV value or passing args.
      cpl run:detached 'LOG_LEVEL=warn rails db:migrate' -a $APP_NAME

      # COMMAND may also be passed at the end (in this case, no need to quote).
      cpl run:detached -a $APP_NAME -- rails db:migrate

      # Uses some other image.
      cpl run:detached rails db:migrate -a $APP_NAME --image /some/full/image/path

      # Uses latest app image (which may not be promoted yet).
      cpl run:detached rails db:migrate -a $APP_NAME --image latest

      # Uses a different image (which may not be promoted yet).
      cpl run:detached rails db:migrate -a $APP_NAME --image appimage:123 # Exact image name
      cpl run:detached rails db:migrate -a $APP_NAME --image latest       # Latest sequential image

      # Uses a different workload than `one_off_workload` from `.controlplane/controlplane.yml`.
      cpl run:detached rails db:migrate:status -a $APP_NAME -w other-workload
      ```
    EX

    WORKLOAD_SLEEP_CHECK = 2

    attr_reader :location, :workload, :one_off, :container

    def call # rubocop:disable Metrics/MethodLength
      @location = config[:default_location]
      @workload = config.options["workload"] || config[:one_off_workload]
      @one_off = "#{workload}-runner-#{rand(1000..9999)}"

      step("Cloning workload '#{workload}' on app '#{config.options[:app]}' to '#{one_off}'") do
        clone_workload
      end

      wait_for_workload(one_off)
      show_logs_waiting
    ensure
      if cp.fetch_workload(one_off)
        progress.puts
        ensure_workload_deleted(one_off)
      end
      exit(1) if @crashed
    end

    private

    def clone_workload # rubocop:disable Metrics/MethodLength
      # Get base specs of workload
      spec = cp.fetch_workload!(workload).fetch("spec")
      container_spec = spec["containers"].detect { _1["name"] == workload } || spec["containers"].first
      @container = container_spec["name"]

      # remove other containers if any
      spec["containers"] = [container_spec]

      # Set runner
      container_spec["command"] = "bash"
      container_spec["args"] = ["-c", 'eval "$CONTROLPLANE_RUNNER"']

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

      # Set cron job props
      spec["type"] = "cron"
      spec["job"] = { "schedule" => "* * * * *", "restartPolicy" => "Never" }
      spec["defaultOptions"]["autoscaling"] = {}
      container_spec.delete("ports")

      container_spec["env"] ||= []
      container_spec["env"] << { "name" => "CONTROLPLANE_TOKEN", "value" => ControlplaneApiDirect.new.api_token }
      container_spec["env"] << { "name" => "CONTROLPLANE_RUNNER", "value" => runner_script }

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
      progress.puts("Scheduled, fetching logs (it's a cron job, so it may take up to a minute to start)...\n\n")
      begin
        while cp.fetch_workload(one_off)
          sleep(WORKLOAD_SLEEP_CHECK)
          print_uniq_logs
        end
      rescue RuntimeError => e
        progress.puts(Shell.color("ERROR: #{e}", :red))
        retry
      end
      progress.puts("\nFinished workload and logger.")
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
