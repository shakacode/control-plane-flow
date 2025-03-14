# frozen_string_literal: true

module Command
  class Run < Base # rubocop:disable Metrics/ClassLength
    INTERACTIVE_COMMANDS = [
      "bash",
      "rails console",
      "rails c",
      "rails dbconsole",
      "rails db"
    ].freeze

    NAME = "run"
    USAGE = "run COMMAND"
    REQUIRES_ARGS = true
    DEFAULT_ARGS = ["bash"].freeze
    OPTIONS = [
      app_option(required: true),
      image_option,
      log_method_option,
      workload_option,
      location_option,
      use_local_token_option,
      terminal_size_option,
      interactive_option,
      detached_option,
      cpu_option,
      memory_option,
      entrypoint_option
    ].freeze
    DESCRIPTION = "Runs one-off interactive or non-interactive replicas (analog of `heroku run`)"
    LONG_DESCRIPTION = <<~DESC
      - Runs one-off interactive or non-interactive replicas (analog of `heroku run`)
      - Uses `Cron` workload type and either:
      - - `cpln workload exec` for interactive mode, with CLI streaming
      - - log async fetching for non-interactive mode
      - The Dockerfile entrypoint is used as the command by default, which assumes `exec "${@}"` to be present,
        and the args ["bash", "-c", cmd_to_run] are passed
      - The entrypoint can be overridden through `--entrypoint`, which must be a single command or a script path that exists in the container,
        and the args ["bash", "-c", cmd_to_run] are passed,
        unless the entrypoint is `bash`, in which case the args ["-c", cmd_to_run] are passed
      - Providing `--entrypoint none` sets the entrypoint to `bash` by default
      - If `fix_terminal_size` is `true` in the `.controlplane/controlplane.yml` file,
        the remote terminal size will be fixed to match the local terminal size (may also be overridden through `--terminal-size`)
      - By default, all jobs use a CPU size of 1 (1 core) and a memory size of 2Gi (2 gibibytes)
        (can be configured through `runner_job_default_cpu` and `runner_job_default_memory` in `controlplane.yml`,
        and also overridden per job through `--cpu` and `--memory`)
      - By default, the job is stopped if it takes longer than 6 hours to finish
        (can be configured though `runner_job_timeout` in `controlplane.yml`)
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Opens shell (bash by default).
      cpflow run -a $APP_NAME

      # Runs interactive command, keeps shell open, and stops job when exiting.
      cpflow run -a $APP_NAME --interactive -- rails c

      # Some commands are automatically detected as interactive, so no need to pass `--interactive`.
      #{INTERACTIVE_COMMANDS.map { |cmd| "cpflow run -a $APP_NAME -- #{cmd}" }.join("\n      ")}

      # Runs non-interactive command, outputs logs, exits with the exit code of the command and stops job.
      cpflow run -a $APP_NAME -- rails db:migrate

      # Runs non-iteractive command, detaches, exits with 0, and prints commands to:
      # - see logs from the job
      # - stop the job
      cpflow run -a $APP_NAME --detached -- rails db:migrate

      # The command needs to be quoted if setting an env variable or passing args.
      cpflow run -a $APP_NAME -- 'SOME_ENV_VAR=some_value rails db:migrate'

      # Uses a different image (which may not be promoted yet).
      cpflow run -a $APP_NAME --image appimage:123 -- rails db:migrate # Exact image name
      cpflow run -a $APP_NAME --image latest -- rails db:migrate       # Latest sequential image

      # Uses a different workload than `one_off_workload` from `.controlplane/controlplane.yml`.
      cpflow run -a $APP_NAME -w other-workload -- bash

      # Overrides remote CPLN_TOKEN env variable with local token.
      # Useful when superuser rights are needed in remote container.
      cpflow run -a $APP_NAME --use-local-token -- bash

      # Replaces the existing Dockerfile entrypoint with `bash`.
      cpflow run -a $APP_NAME --entrypoint none -- rails db:migrate

      # Replaces the existing Dockerfile entrypoint.
      cpflow run -a $APP_NAME --entrypoint /app/alternative-entrypoint.sh -- rails db:migrate
      ```
    EX

    DEFAULT_JOB_CPU = "1"
    DEFAULT_JOB_MEMORY = "2Gi"
    DEFAULT_JOB_TIMEOUT = 21_600 # 6 hours
    DEFAULT_JOB_HISTORY_LIMIT = 10
    MAGIC_END = "---cpflow run command finished---"

    attr_reader :interactive, :detached, :location, :original_workload, :runner_workload,
                :default_image, :default_cpu, :default_memory, :job_timeout, :job_history_limit,
                :container, :expected_deployed_version, :job, :replica, :command

    def call # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      @interactive = config.options[:interactive] || interactive_command?
      @detached = config.options[:detached]
      @log_method = config.options[:log_method]

      @location = config.location
      @original_workload = config.options[:workload] || config[:one_off_workload]
      @runner_workload = "#{original_workload}-runner"
      @default_image = "#{config.app}:#{Controlplane::NO_IMAGE_AVAILABLE}"
      @default_cpu = config.current[:runner_job_default_cpu] || DEFAULT_JOB_CPU
      @default_memory = config.current[:runner_job_default_memory] || DEFAULT_JOB_MEMORY
      @job_timeout = config.current[:runner_job_timeout] || DEFAULT_JOB_TIMEOUT
      @job_history_limit = DEFAULT_JOB_HISTORY_LIMIT

      unless interactive
        @internal_sigint = false

        # Catch Ctrl+C in the main process
        trap("SIGINT") do
          unless @internal_sigint
            print_detached_commands
            exit(ExitCode::INTERRUPT)
          end
        end
      end

      create_runner_workload if cp.fetch_workload(runner_workload).nil?
      wait_for_runner_workload_deploy
      update_runner_workload
      wait_for_runner_workload_update if expected_deployed_version

      start_job
      wait_for_replica_for_job

      progress.puts
      if interactive
        run_interactive
      else
        run_non_interactive
      end
    end

    private

    def interactive_command?
      INTERACTIVE_COMMANDS.include?(args_join(config.args))
    end

    def app_workload_replica_args
      ["-a", config.app, "--workload", runner_workload, "--replica", replica]
    end

    def create_runner_workload # rubocop:disable Metrics/MethodLength
      step("Creating runner workload '#{runner_workload}' based on '#{original_workload}'") do
        spec, container_spec = base_workload_specs(original_workload)

        # Remove other containers if any
        spec["containers"] = [container_spec]

        # Default to using existing Dockerfile entrypoint
        container_spec.delete("command")

        # Remove props that conflict with job
        container_spec.delete("ports")
        container_spec.delete("lifecycle")
        container_spec.delete("livenessProbe")
        container_spec.delete("readinessProbe")

        # Set image, CPU, and memory to default values
        container_spec["image"] = default_image
        container_spec["cpu"] = default_cpu
        container_spec["memory"] = default_memory

        # Ensure cron workload won't run per schedule
        spec["defaultOptions"]["suspend"] = true

        # Ensure no scaling
        spec["defaultOptions"]["autoscaling"] = {}
        spec["defaultOptions"]["capacityAI"] = false

        # Set cron job props
        spec["type"] = "cron"
        spec["job"] = {
          # Next job set to run on January 1st, 2029
          "schedule" => "0 0 1 1 1",

          "restartPolicy" => "Never",
          "activeDeadlineSeconds" => job_timeout,
          "historyLimit" => job_history_limit
        }

        # Create runner workload
        cp.apply_hash("kind" => "workload", "name" => runner_workload, "spec" => spec)
      end
    end

    def update_runner_workload # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      should_update = false
      spec = nil

      step("Checking if runner workload '#{runner_workload}' needs to be updated") do # rubocop:disable Metrics/BlockLength
        _, original_container_spec = base_workload_specs(original_workload)
        spec, container_spec = base_workload_specs(runner_workload)

        # Keep ENV synced between original and runner workloads
        original_env_str = original_container_spec["env"]&.sort_by { |env| env["name"] }.to_s
        env_str = container_spec["env"]&.sort_by { |env| env["name"] }.to_s
        if original_env_str != env_str
          container_spec["env"] = original_container_spec["env"] || []
          should_update = true
        end

        if container_spec["image"] != default_image
          container_spec["image"] = default_image
          should_update = true
        end

        if container_spec["cpu"] != default_cpu
          container_spec["cpu"] = default_cpu
          should_update = true
        end

        if container_spec["memory"] != default_memory
          container_spec["memory"] = default_memory
          should_update = true
        end

        if spec["job"]["activeDeadlineSeconds"] != job_timeout
          spec["job"]["activeDeadlineSeconds"] = job_timeout
          should_update = true
        end

        if spec["job"]["historyLimit"] != job_history_limit
          spec["job"]["historyLimit"] = job_history_limit
          should_update = true
        end

        true
      end

      return unless should_update

      step("Updating runner workload '#{runner_workload}'") do
        # Update runner workload
        @expected_deployed_version = (cp.cron_workload_deployed_version(runner_workload) || 0) + 1
        cp.apply_hash("kind" => "workload", "name" => runner_workload, "spec" => spec)
      end
    end

    def wait_for_runner_workload_deploy
      step("Waiting for runner workload '#{runner_workload}' to be deployed", retry_on_failure: true) do
        !cp.cron_workload_deployed_version(runner_workload).nil?
      end
    end

    def wait_for_runner_workload_update
      step("Waiting for runner workload '#{runner_workload}' to be updated", retry_on_failure: true) do
        (cp.cron_workload_deployed_version(runner_workload) || 0) >= expected_deployed_version
      end
    end

    def start_job
      job_start_yaml = build_job_start_yaml

      step("Starting job for runner workload '#{runner_workload}'", retry_on_failure: true) do
        result = cp.start_cron_workload(runner_workload, job_start_yaml, location: location)
        @job = result&.dig("items", 0, "id")

        job || false
      end
    end

    def wait_for_replica_for_job
      step("Waiting for replica to start, which runs job '#{job}'", retry_on_failure: true) do
        result = cp.fetch_workload_replicas(runner_workload, location: location)
        @replica = result&.dig("items")&.find { |item| item.include?(job) }

        replica || false
      end
    end

    def run_interactive
      progress.puts("Connecting to replica '#{replica}'...\n\n")
      cp.workload_exec(runner_workload, replica, location: location, container: container, command: command)
    end

    def run_non_interactive
      if detached
        print_detached_commands
        exit(ExitCode::SUCCESS)
      end

      case @log_method
      when 1 then run_non_interactive_v1
      when 2 then run_non_interactive_v2
      when 3 then run_non_interactive_v3
      else raise "Invalid log method: #{@log_method}"
      end
    end

    def run_non_interactive_v1 # rubocop:disable Metrics/MethodLength
      logs_pid = Process.fork do
        # Catch Ctrl+C in the forked process
        trap("SIGINT") do
          exit(ExitCode::SUCCESS)
        end

        run_cpflow_command("logs", *app_workload_replica_args)
      end
      Process.detach(logs_pid)

      exit_status = wait_for_job_status

      # We need to wait a bit for the logs to appear,
      # otherwise it may exit without showing them
      Kernel.sleep(30)

      @internal_sigint = true
      Process.kill("INT", logs_pid)
      exit(exit_status)
    end

    def run_non_interactive_v2
      current_cpflow = File.expand_path("cpflow", "#{__dir__}/../..")
      logs_pipe = IO.popen([current_cpflow, "logs", *app_workload_replica_args])

      exit_status = wait_for_job_status_and_log(logs_pipe)

      @internal_sigint = true
      Process.kill("INT", logs_pipe.pid)
      exit(exit_status)
    end

    def run_non_interactive_v3
      exit(show_logs_waiting)
    end

    def base_workload_specs(workload)
      spec = cp.fetch_workload!(workload).fetch("spec")
      container_spec = spec["containers"].detect { _1["name"] == original_workload } || spec["containers"].first

      [spec, container_spec]
    end

    def build_job_start_yaml # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      _, original_container_spec = base_workload_specs(original_workload)
      @container = original_container_spec["name"]

      job_start_hash = { "name" => container }

      if config.options[:use_local_token]
        job_start_hash["env"] ||= []
        job_start_hash["env"].push({ "name" => "CPFLOW_TOKEN", "value" => ControlplaneApiDirect.new.api_token[:token] })
      end

      entrypoint = nil
      if config.options[:entrypoint]
        entrypoint = config.options[:entrypoint] == "none" ? "bash" : config.options[:entrypoint]
      end

      job_start_hash["command"] = entrypoint if entrypoint
      job_start_hash["args"] ||= []
      job_start_hash["args"].push("bash") unless entrypoint == "bash"
      job_start_hash["args"].push("-c")
      job_start_hash["env"] ||= []
      job_start_hash["env"].push({ "name" => "CPFLOW_RUNNER_SCRIPT", "value" => runner_script })
      if interactive
        job_start_hash["env"].push({ "name" => "CPFLOW_MONITORING_SCRIPT", "value" => interactive_monitoring_script })

        job_start_hash["args"].push('eval "$CPFLOW_MONITORING_SCRIPT"')
        @command = %(bash -c 'eval "$CPFLOW_RUNNER_SCRIPT"')
      else
        job_start_hash["args"].push('eval "$CPFLOW_RUNNER_SCRIPT"')
      end

      image = config.options[:image]
      image_link = if image
                     image = cp.latest_image if image == "latest"
                     "/org/#{config.org}/image/#{image}"
                   else
                     original_container_spec["image"]
                   end

      job_start_hash["image"] = image_link
      job_start_hash["cpu"] = config.options[:cpu] if config.options[:cpu]
      job_start_hash["memory"] = config.options[:memory] if config.options[:memory]

      job_start_hash.to_yaml
    end

    def interactive_monitoring_script
      <<~SCRIPT
        primary_pid=""

        check_primary() {
          if ! kill -0 $primary_pid 2>/dev/null; then
            echo "Primary process has exited. Shutting down."
            exit 0
          fi
        }

        while true; do
          if [[ -z "$primary_pid" ]]; then
            primary_pid=$(ps -eo pid,etime,cmd --sort=etime | grep -v "$$" | grep -v 'ps -eo' | grep -v 'grep' | grep 'CPFLOW_RUNNER_SCRIPT' | head -n 1 | awk '{print $1}')
            if [[ ! -z "$primary_pid" ]]; then
              echo "Primary process set with PID: $primary_pid"
            fi
          else
            check_primary
          fi

          sleep 1
        done
      SCRIPT
    end

    def interactive_runner_script
      script = ""

      # NOTE: fixes terminal size to match local terminal
      if config.current[:fix_terminal_size] || config.options[:terminal_size]
        if config.options[:terminal_size]
          rows, cols = config.options[:terminal_size].split(",")
        else
          # NOTE: cannot use `Shell.cmd` here, as `stty size` has to run in a terminal environment
          rows, cols = `stty size`.split(/\s+/)
        end
        script += "stty rows #{rows}\nstty cols #{cols}\n"
      end

      script
    end

    def runner_script # rubocop:disable Metrics/MethodLength
      script = <<~SCRIPT
        unset CPFLOW_RUNNER_SCRIPT
        unset CPFLOW_MONITORING_SCRIPT

        if [ -n "$CPFLOW_TOKEN" ]; then
          CPLN_TOKEN=$CPFLOW_TOKEN
          unset CPFLOW_TOKEN
        fi
      SCRIPT

      script += interactive_runner_script if interactive

      script +=
        if @log_method == 1 || @interactive
          args_join(config.args)
        else
          <<~SCRIPT
            ( #{args_join(config.args)} )
            CPFLOW_EXIT_CODE=$?
            echo '#{MAGIC_END}'
            exit $CPFLOW_EXIT_CODE
          SCRIPT
        end

      script
    end

    def wait_for_job_status
      Kernel.sleep(1) until (exit_code = resolve_job_status)
      exit_code
    end

    def wait_for_job_status_and_log(logs_pipe) # rubocop:disable Metrics/MethodLength
      no_logs_counter = 0

      loop do
        no_logs_counter += 1
        break if no_logs_counter > 60 # 30s
        break if logs_pipe.eof?
        next Kernel.sleep(0.5) unless logs_pipe.ready?

        no_logs_counter = 0
        line = logs_pipe.gets
        break if line.chomp == MAGIC_END

        puts(line)
      end

      resolve_job_status
    end

    def print_detached_commands
      return unless replica

      app_workload_replica_config = app_workload_replica_args.join(" ")
      progress.puts(
        "\n\n" \
        "- To view logs from the job, run:\n  `cpflow logs #{app_workload_replica_config}`\n" \
        "- To stop the job, run:\n  `cpflow ps:stop #{app_workload_replica_config}`\n"
      )
    end

    def resolve_job_status # rubocop:disable Metrics/MethodLength
      loop do
        result = cp.fetch_cron_workload(runner_workload, location: location)
        job_details = result&.dig("items")&.find { |item| item["id"] == job }
        status = job_details&.dig("status")

        Shell.debug("JOB STATUS", status)

        case status
        when "active", "pending"
          sleep 1
        when "successful"
          break ExitCode::SUCCESS
        else
          break ExitCode::ERROR_DEFAULT
        end
      end
    end

    ###########################################
    ### temporary extaction from run:detached
    ###########################################
    def show_logs_waiting # rubocop:disable Metrics/MethodLength
      retries = 0
      begin
        job_finished_count = 0
        loop do
          case print_uniq_logs
          when :finished
            break
          when :changed
            next
          else
            job_finished_count += 1 if resolve_job_status
            break if job_finished_count > 5

            sleep(1)
          end
        end

        resolve_job_status
      rescue RuntimeError => e
        raise "#{e} Exiting..." unless retries < 10 # MAX_RETRIES

        progress.puts(Shell.color("ERROR: #{e} Retrying...", :red))
        retries += 1
        retry
      end
    end

    def print_uniq_logs
      status = nil

      @printed_log_entries ||= []
      ts = Time.now.to_i
      entries = normalized_log_entries(from: ts - 60, to: ts)

      (entries - @printed_log_entries).sort.each do |(_ts, val)|
        status ||= :changed
        val.chomp == MAGIC_END ? status = :finished : progress.puts(val)
      end

      @printed_log_entries = entries # as well truncate old entries if any

      status || :unchanged
    end

    def normalized_log_entries(from:, to:)
      log = cp.log_get(workload: runner_workload, from: from, to: to, replica: replica)

      log["data"]["result"]
        .each_with_object([]) { |obj, result| result.concat(obj["values"]) }
        .select { |ts, _val| ts[..-10].to_i > from }
    end
  end
end
