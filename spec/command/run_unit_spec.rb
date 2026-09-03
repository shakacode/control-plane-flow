# frozen_string_literal: true

require "spec_helper"

describe Command::Run do
  describe "CLI command argument handling" do
    it "preserves special-character arguments as exact remote command arguments" do
      payloads = [
        "two words",
        "single'quote",
        'double"quote',
        "$HOME",
        "`printf injected`",
        "semi;colon"
      ]
      runner_script = nil
      app = dummy_test_app

      stub_env("DISABLE_VALIDATIONS", "true")
      allow_any_instance_of(described_class).to receive(:call) do |command| # rubocop:disable RSpec/AnyInstance
        command.instance_variable_set(:@interactive, false)
        command.instance_variable_set(:@log_method, 3)
        runner_script = command.send(:runner_script)
      end

      result = run_cpflow_command(
        "run", "--app", app, "--org", "test-org", "--",
        "printf", "<%s>\\n", *payloads
      )

      expect(result[:status]).to eq(ExitCode::SUCCESS), result.inspect
      expect(runner_script).not_to be_nil

      output, error_output, status = Open3.capture3("bash", "-c", runner_script)

      expect(status).to be_success, error_output
      expect(output.lines(chomp: true)).to eq(payloads.map { |payload| "<#{payload}>" } + [described_class::MAGIC_END])
    end

    it "preserves intentional shell syntax in a single command string" do
      runner_script = nil
      app = dummy_test_app

      stub_env("DISABLE_VALIDATIONS", "true")
      allow_any_instance_of(described_class).to receive(:call) do |command| # rubocop:disable RSpec/AnyInstance
        command.instance_variable_set(:@interactive, false)
        command.instance_variable_set(:@log_method, 3)
        runner_script = command.send(:runner_script)
      end

      result = run_cpflow_command(
        "run", "--app", app, "--org", "test-org", "--",
        "printf 'left\\n'; printf 'right\\n'"
      )

      expect(result[:status]).to eq(ExitCode::SUCCESS), result.inspect
      expect(runner_script).not_to be_nil

      output, error_output, status = Open3.capture3("bash", "-c", runner_script)

      expect(status).to be_success, error_output
      expect(output.lines(chomp: true)).to eq(["left", "right", described_class::MAGIC_END])
    end

    it "uses one ordered stream for payload stderr and the finish marker without changing the exit status" do
      runner_script = nil
      app = dummy_test_app

      stub_env("DISABLE_VALIDATIONS", "true")
      allow_any_instance_of(described_class).to receive(:call) do |command| # rubocop:disable RSpec/AnyInstance
        command.instance_variable_set(:@interactive, false)
        command.instance_variable_set(:@log_method, 3)
        runner_script = command.send(:runner_script)
      end

      result = run_cpflow_command(
        "run", "--app", app, "--org", "test-org", "--",
        "ruby", "-e", "warn 'payload stderr'; exit 23"
      )

      expect(result[:status]).to eq(ExitCode::SUCCESS), result.inspect
      expect(runner_script).to match(
        /\) 2>&1\nCPFLOW_EXIT_CODE=\$\?\necho '#{Regexp.escape(described_class::MAGIC_END)}'/
      )

      output, error_output, status = Open3.capture3("bash", "-c", runner_script)

      expect(status.exitstatus).to eq(23)
      expect(error_output).to be_empty
      expect(output.lines(chomp: true)).to eq(["payload stderr", described_class::MAGIC_END])
    end
  end

  describe "#call" do
    let(:config) do
      instance_double(
        Config,
        app: "test-app",
        args: ["bin/rails db:migrate"],
        current: {},
        location: "aws-us-east-2",
        options: { interactive: false, detached: false, log_method: 3 }
      )
    end
    let(:cp) { instance_double(Controlplane) }
    let(:progress) { instance_double(IO, puts: nil) }
    let(:command) { described_class.new(config) }

    before do
      allow(config).to receive(:[]).with(:one_off_workload).and_return("rails")
      allow(command).to receive_messages(cp: cp, progress: progress)
      allow(cp).to receive(:fetch_workload).with("rails-runner").and_return({})
      allow(command).to receive(:update_runner_workload)
      allow(command).to receive(:start_job)
      allow(command).to receive(:wait_for_replica_for_job) do
        command.instance_variable_set(:@job_completed_before_replica_exit_status, ExitCode::SUCCESS)
      end
      allow(command).to receive(:run_non_interactive)
    end

    it "exits with the cron job status when the job finishes before a replica is observed" do
      expect { command.call }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(ExitCode::SUCCESS)
      end

      expect(command).not_to have_received(:run_non_interactive)
    end
  end

  describe "#update_runner_workload" do
    let(:config) { instance_double(Config) }
    let(:cp) { instance_double(Controlplane) }
    let(:command) { described_class.new(config) }
    let(:workload_identities) { { original: "//identity/test-app-identity", runner: nil } }
    let(:workload_specs) do
      original_spec = {}
      original_spec["identityLink"] = workload_identities[:original] if workload_identities[:original]
      original_container_spec = {
        "env" => [{ "name" => "SECRET_KEY_BASE", "value" => "cpln://secret/app.SECRET_KEY_BASE" }]
      }
      runner_container_spec = {
        "env" => original_container_spec["env"],
        "image" => "test-app:#{Controlplane::NO_IMAGE_AVAILABLE}",
        "cpu" => described_class::DEFAULT_JOB_CPU,
        "memory" => described_class::DEFAULT_JOB_MEMORY
      }
      runner_spec = {
        "containers" => [runner_container_spec],
        "defaultOptions" => {},
        "job" => {
          "activeDeadlineSeconds" => described_class::DEFAULT_JOB_TIMEOUT,
          "historyLimit" => described_class::DEFAULT_JOB_HISTORY_LIMIT
        }
      }
      runner_spec["identityLink"] = workload_identities[:runner] if workload_identities[:runner]

      {
        original_spec: original_spec,
        original_container_spec: original_container_spec,
        runner_spec: runner_spec,
        runner_container_spec: runner_container_spec
      }
    end

    before do
      allow(command).to receive(:cp).and_return(cp)
      allow(command).to receive(:step).and_yield
      allow(command).to receive(:base_workload_specs)
        .with("rails")
        .and_return([workload_specs[:original_spec], workload_specs[:original_container_spec]])
      allow(command).to receive(:base_workload_specs)
        .with("rails-runner")
        .and_return([workload_specs[:runner_spec], workload_specs[:runner_container_spec]])
      allow(cp).to receive(:apply_hash)

      command.instance_variable_set(:@original_workload, "rails")
      command.instance_variable_set(:@runner_workload, "rails-runner")
      command.instance_variable_set(:@default_image, "test-app:#{Controlplane::NO_IMAGE_AVAILABLE}")
      command.instance_variable_set(:@default_cpu, described_class::DEFAULT_JOB_CPU)
      command.instance_variable_set(:@default_memory, described_class::DEFAULT_JOB_MEMORY)
      command.instance_variable_set(:@job_timeout, described_class::DEFAULT_JOB_TIMEOUT)
      command.instance_variable_set(:@job_history_limit, described_class::DEFAULT_JOB_HISTORY_LIMIT)
    end

    it "syncs the original workload identity link to the runner workload" do
      command.send(:update_runner_workload)

      expect(cp).to have_received(:apply_hash).with(
        { "kind" => "workload", "name" => "rails-runner", "spec" => workload_specs[:runner_spec] },
        wait: true
      )
      expect(workload_specs[:runner_spec]["identityLink"]).to eq("//identity/test-app-identity")
    end

    context "when the original workload has no identity link" do
      let(:workload_identities) { { original: nil, runner: "//identity/stale-app-identity" } }

      it "removes the stale identity link from the runner workload" do
        command.send(:update_runner_workload)

        expect(cp).to have_received(:apply_hash).with(
          { "kind" => "workload", "name" => "rails-runner", "spec" => workload_specs[:runner_spec] },
          wait: true
        )
        expect(workload_specs[:runner_spec]).not_to have_key("identityLink")
      end
    end

    context "when the identity links are already in sync" do
      let(:workload_identities) do
        { original: "//identity/test-app-identity", runner: "//identity/test-app-identity" }
      end

      it "does not update the runner workload" do
        command.send(:update_runner_workload)

        expect(cp).not_to have_received(:apply_hash)
      end
    end
  end

  describe "#build_job_start_yaml" do
    let(:gvc_data) do
      {
        "id" => "36f3cf5b-cdfc-466c-9d21-43cc3888d496",
        "name" => "test-app",
        "created" => "2026-08-28T00:54:48.648Z"
      }
    end
    let(:config) do
      instance_double(
        Config,
        args: ["bin/rails db:migrate"],
        current: {},
        options: { use_local_token: false, entrypoint: nil, image: nil, cpu: nil, memory: nil }
      )
    end
    let(:cp) { instance_double(Controlplane) }
    let(:command) { described_class.new(config) }
    let(:job_env) { YAML.safe_load(command.send(:build_job_start_yaml)).fetch("env") }

    def env_value(name)
      job_env.find { |env_var| env_var["name"] == name }&.fetch("value")
    end

    before do
      allow(command).to receive_messages(cp: cp)
      allow(command).to receive(:base_workload_specs)
        .with("rails")
        .and_return([{}, { "name" => "rails", "image" => "/org/test-org/image/test-app:1" }])
      allow(cp).to receive(:fetch_gvc).and_return(gvc_data)

      command.instance_variable_set(:@original_workload, "rails")
      command.instance_variable_set(:@interactive, false)
      command.instance_variable_set(:@log_method, 3)
    end

    it "injects the immutable GVC identity into the job environment" do
      expect(job_env).to include(
        { "name" => "CPFLOW_GVC_ID", "value" => "36f3cf5b-cdfc-466c-9d21-43cc3888d496" },
        { "name" => "CPFLOW_GVC_CREATED", "value" => "2026-08-28T00:54:48.648Z" }
      )
    end

    it "still passes the command through the runner script" do
      runner_script = job_env.find { |env_var| env_var["name"] == "CPFLOW_RUNNER_SCRIPT" }

      expect(runner_script["value"]).to include("bin/rails db:migrate")
    end

    context "when the command is interactive" do
      before do
        command.instance_variable_set(:@interactive, true)
      end

      it "stores the remote runner invocation as exact command arguments" do
        command.send(:build_job_start_yaml)

        expect(command.command).to eq(["bash", "-c", 'eval "$CPFLOW_RUNNER_SCRIPT"'])
      end
    end

    context "when the app has no GVC" do
      let(:gvc_data) { nil }

      it "sets both to empty, so an inherited value cannot pass as a live identity" do
        expect(env_value("CPFLOW_GVC_ID")).to eq("")
        expect(env_value("CPFLOW_GVC_CREATED")).to eq("")
      end
    end

    context "when the GVC has an id but no creation timestamp" do
      let(:gvc_data) { { "id" => "36f3cf5b-cdfc-466c-9d21-43cc3888d496", "name" => "test-app" } }

      it "empties the timestamp, so a live id is never paired with an inherited one" do
        expect(env_value("CPFLOW_GVC_ID")).to eq("36f3cf5b-cdfc-466c-9d21-43cc3888d496")
        expect(env_value("CPFLOW_GVC_CREATED")).to eq("")
      end
    end

    context "when the token may not read the GVC" do
      before do
        forbidden_error = ControlplaneApiDirect::ForbiddenError.new(
          url: "/org/test-org/gvc/test-app", response: "403 Forbidden"
        )
        allow(cp).to receive(:fetch_gvc).and_raise(forbidden_error)
        allow(Shell).to receive(:warn)
      end

      it "still builds the job, because `run` never required GVC-read access" do
        expect(env_value("CPFLOW_RUNNER_SCRIPT")).to include("bin/rails db:migrate")
        expect(env_value("CPFLOW_GVC_ID")).to eq("")
        expect(env_value("CPFLOW_GVC_CREATED")).to eq("")
      end

      it "names the missing grant, which the error message itself does not" do
        job_env

        expect(Shell).to have_received(:warn).with(/`view` on kind `gvc`/)
      end

      it "says the variables are set to empty rather than absent" do
        job_env

        expect(Shell).to have_received(:warn).with(/set to empty strings/)
      end
    end

    # The API layer raises a bare RuntimeError for 401 and 5xx, so the rescue is intentionally wider
    # than ForbiddenError. Narrowing it would fail deploys on a transient GVC-endpoint error.
    context "when the GVC endpoint fails without a typed error" do
      before do
        allow(cp).to receive(:fetch_gvc).and_raise(RuntimeError, "500 Internal Server Error")
        allow(Shell).to receive(:warn)
      end

      it "still builds the job" do
        expect(env_value("CPFLOW_RUNNER_SCRIPT")).to include("bin/rails db:migrate")
        expect(env_value("CPFLOW_GVC_ID")).to eq("")
      end
    end

    context "when the GVC has no id" do
      let(:gvc_data) { { "name" => "test-app", "created" => "2026-08-28T00:54:48.648Z" } }

      it "sets both to empty, so an inherited value cannot pass as a live identity" do
        expect(env_value("CPFLOW_GVC_ID")).to eq("")
        expect(env_value("CPFLOW_GVC_CREATED")).to eq("")
      end
    end
  end

  describe "#run_interactive" do
    let(:config) { instance_double(Config, app: "test-app") }
    let(:cp) { instance_double(Controlplane) }
    let(:progress) { instance_double(IO, puts: nil) }
    let(:command) { described_class.new(config) }

    before do
      allow(command).to receive_messages(cp: cp, progress: progress)
      command.instance_variable_set(:@runner_workload, "rails-runner")
      command.instance_variable_set(:@replica, "rails-runner-12345")
      command.instance_variable_set(:@location, "aws-us-east-2")
      command.instance_variable_set(:@container, "rails")
      command.instance_variable_set(:@command, ["bash", "-c", 'eval "$CPFLOW_RUNNER_SCRIPT"'])
      allow(cp).to receive(:workload_exec).and_return(exec_success)
    end

    context "when cpln workload exec exits successfully" do
      let(:exec_success) { true }

      it "does not print a cleanup hint" do
        command.send(:run_interactive)

        expect(cp).to have_received(:workload_exec).with(
          "rails-runner", "rails-runner-12345",
          location: "aws-us-east-2", container: "rails",
          command: ["bash", "-c", 'eval "$CPFLOW_RUNNER_SCRIPT"']
        ).once
        expect(progress).not_to have_received(:puts).with(/runner workload is still running/)
      end
    end

    shared_examples "an aborted interactive session" do |expected_exit_code|
      it "prints the cleanup hint instead of the generic error" do
        expect { command.send(:run_interactive) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(expected_exit_code)
        end

        expect(progress).to have_received(:puts).with(
          satisfy do |msg|
            msg.include?("cpflow ps:stop") &&
              msg.include?("-a test-app") &&
              msg.include?("--workload rails-runner") &&
              msg.include?("--replica rails-runner-12345") &&
              msg.include?("--location aws-us-east-2")
          end
        )
      end
    end

    context "when cpln workload exec exits with a non-zero status" do
      let(:exec_success) { false }

      it_behaves_like "an aborted interactive session", ExitCode::ERROR_DEFAULT
    end

    context "when cpln workload exec is killed by a signal" do
      let(:exec_success) { nil }

      it_behaves_like "an aborted interactive session", ExitCode::INTERRUPT
    end
  end

  describe "#show_logs_waiting" do
    let(:command) { described_class.allocate }
    let(:progress) { instance_double(IO, puts: nil) }

    it "continues beyond the former 30-second horizon for delayed logs" do
      now = 0.0
      wall_time = 1_788_000_000

      allow(command).to receive(:print_uniq_logs)
        .and_return(*Array.new(31, :unchanged), :finished)
      allow(command).to receive(:current_job_status).and_return("successful")
      allow(command).to receive(:monotonic_time) { now }
      allow(Time).to receive(:now).and_return(Time.at(wall_time))
      allow(Kernel).to receive(:sleep) { |duration| now += duration }

      result = command.send(:show_logs_waiting)

      expect(result).to eq(ExitCode::SUCCESS)
      expect(command).to have_received(:print_uniq_logs).exactly(32).times
      expect(command).to have_received(:current_job_status).once
      expect(Kernel).to have_received(:sleep).with(1).exactly(31).times
      expect(command.instance_variable_get(:@post_terminal_log_from))
        .to eq(wall_time - described_class::LOG_QUERY_LOOKBACK_SECONDS)
    end

    it "drains delayed logs for a bounded window after the job finishes and preserves its exit status" do
      now = 0.0

      allow(command).to receive(:print_uniq_logs)
        .and_return(*Array.new(7, :unchanged), :finished)
      allow(command).to receive(:current_job_status).and_return("failed")
      allow(command).to receive(:monotonic_time) { now }
      allow(Kernel).to receive(:sleep) { |duration| now += duration }

      result = command.send(:show_logs_waiting)

      expect(result).to eq(ExitCode::ERROR_DEFAULT)
      expect(command).to have_received(:print_uniq_logs).exactly(8).times
      expect(command).to have_received(:current_job_status).once
      expect(Kernel).to have_received(:sleep).with(1).exactly(7).times
    end

    it "stops draining when the post-terminal log window expires" do
      now = 0.0
      expected_polls = described_class::POST_TERMINAL_LOG_DRAIN_SECONDS

      allow(command).to receive_messages(
        print_uniq_logs: :unchanged,
        current_job_status: "successful"
      )
      allow(command).to receive(:monotonic_time) { now }
      allow(Kernel).to receive(:sleep) { |duration| now += duration }

      result = command.send(:show_logs_waiting)

      expect(result).to eq(ExitCode::SUCCESS)
      expect(command).to have_received(:print_uniq_logs).exactly(expected_polls).times
      expect(command).to have_received(:current_job_status).once
      expect(Kernel).to have_received(:sleep).with(1).exactly(expected_polls).times
    end

    it "does not let changing log entries extend the post-terminal deadline" do
      now = 0.0
      request_duration = described_class::POST_TERMINAL_LOG_DRAIN_SECONDS / 3.0

      allow(command).to receive(:print_uniq_logs) do
        now += request_duration
        :changed
      end
      allow(command).to receive_messages(
        current_job_status: "failed",
        resolve_job_status: ExitCode::ERROR_DEFAULT
      )
      allow(command).to receive(:monotonic_time) { now }
      allow(Kernel).to receive(:sleep) { |duration| now += duration }

      result = command.send(:show_logs_waiting)

      expect(result).to eq(ExitCode::ERROR_DEFAULT)
      expect(command).to have_received(:print_uniq_logs).exactly(4).times
      expect(command).to have_received(:current_job_status).once
      expect(command).not_to have_received(:resolve_job_status)
      expect(Kernel).to have_received(:sleep).with(1).exactly(3).times
    end

    [nil, "active", "pending"].each do |nonterminal_status|
      status_label = nonterminal_status || "unavailable"

      it "throttles changed-log polling while the cron status is #{status_label}" do
        now = 0.0

        allow(command).to receive(:print_uniq_logs).and_return(:changed, :changed, :finished)
        allow(command).to receive(:current_job_status).and_return(nonterminal_status, "successful")
        allow(command).to receive(:resolve_job_status).and_return(ExitCode::ERROR_DEFAULT)
        allow(command).to receive(:monotonic_time) { now }
        allow(Kernel).to receive(:sleep) { |duration| now += duration }

        result = command.send(:show_logs_waiting)

        expect(result).to eq(ExitCode::SUCCESS)
        expect(command).to have_received(:print_uniq_logs).exactly(3).times
        expect(command).to have_received(:current_job_status).twice
        expect(command).not_to have_received(:resolve_job_status)
        expect(Kernel).to have_received(:sleep).with(1).twice
      end
    end

    it "keeps a bounded status outage provisional until an authoritative success arrives" do
      now = 0.0
      unavailable_streak = Array.new(described_class::JOB_STATUS_UNAVAILABLE_RETRY_LIMIT + 1)
      statuses = [*unavailable_streak, "successful"]

      allow(command).to receive(:print_uniq_logs)
        .and_return(*Array.new(statuses.length, :changed), :finished)
      allow(command).to receive(:current_job_status).and_return(*statuses)
      allow(command).to receive(:resolve_job_status).and_return(ExitCode::ERROR_DEFAULT)
      allow(command).to receive(:monotonic_time) { now }
      allow(Kernel).to receive(:sleep) { |duration| now += duration }

      result = command.send(:show_logs_waiting)

      expect(result).to eq(ExitCode::SUCCESS)
      expect(command).to have_received(:current_job_status).exactly(statuses.length).times
      expect(command).not_to have_received(:resolve_job_status)
    end

    it "latches an authoritative failure that arrives after a bounded status outage" do
      now = 0.0
      unavailable_streak = Array.new(described_class::JOB_STATUS_UNAVAILABLE_RETRY_LIMIT + 1)
      statuses = [*unavailable_streak, "failed"]

      allow(command).to receive(:print_uniq_logs)
        .and_return(*Array.new(statuses.length, :changed), :finished)
      allow(command).to receive(:current_job_status).and_return(*statuses)
      allow(command).to receive(:monotonic_time) { now }
      allow(Kernel).to receive(:sleep) { |duration| now += duration }
      allow(Shell).to receive(:warn)

      result = command.send(:show_logs_waiting)

      expect(result).to eq(ExitCode::ERROR_DEFAULT)
      expect(command).to have_received(:current_job_status).exactly(statuses.length).times
      expect(Shell).not_to have_received(:warn)
    end

    it "starts one fixed reconciliation deadline when the sixth status is unavailable" do
      now = 0.0
      wall_time = 1_788_000_000

      allow(command).to receive_messages(print_uniq_logs: :changed, current_job_status: nil)
      allow(command).to receive(:monotonic_time) { now }
      allow(Time).to receive(:now).and_return(Time.at(wall_time))
      allow(Kernel).to receive(:sleep) { |duration| now += duration }
      allow(Shell).to receive(:warn)

      result = command.send(:show_logs_waiting)

      expected_deadline = described_class::JOB_STATUS_UNAVAILABLE_RETRY_LIMIT +
                          described_class::POST_TERMINAL_LOG_DRAIN_SECONDS
      expect(result).to eq(ExitCode::ERROR_DEFAULT)
      expect(now).to eq(expected_deadline)
      expect(command.instance_variable_get(:@post_terminal_log_from))
        .to eq(wall_time - described_class::LOG_QUERY_LOOKBACK_SECONDS)
      expect(Shell).to have_received(:warn).once
    end

    %w[active pending].each do |available_status|
      it "clears an outage-only deadline after status becomes #{available_status}" do
        now = 0.0
        log_polls = 0
        status_index = 0
        last_status = nil
        success_observed_at = nil
        boundary_after_recovery = :not_observed
        unavailable_threshold = Array.new(described_class::JOB_STATUS_UNAVAILABLE_RETRY_LIMIT + 1)
        below_threshold = Array.new(described_class::JOB_STATUS_UNAVAILABLE_RETRY_LIMIT)
        statuses = [*unavailable_threshold, available_status, *below_threshold, "successful"]
        former_deadline = described_class::JOB_STATUS_UNAVAILABLE_RETRY_LIMIT +
                          described_class::POST_TERMINAL_LOG_DRAIN_SECONDS

        allow(command).to receive(:print_uniq_logs) do
          log_polls += 1
          if log_polls == unavailable_threshold.length + 2
            boundary_after_recovery = command.instance_variable_get(:@post_terminal_log_from)
          end
          log_polls > statuses.length ? :finished : :changed
        end
        allow(command).to receive(:current_job_status) do
          last_status = statuses[status_index]
          status_index += 1
          success_observed_at = now if last_status == "successful"
          last_status
        end
        allow(command).to receive(:monotonic_time) { now }
        allow(Time).to receive(:now).and_return(Time.at(1_788_000_000))
        allow(Kernel).to receive(:sleep) do |duration|
          now = last_status == available_status ? former_deadline + 1 : now + duration
        end
        allow(Shell).to receive(:warn)

        result = command.send(:show_logs_waiting)

        expect(result).to eq(ExitCode::SUCCESS)
        expect(success_observed_at).to be > former_deadline
        expect(boundary_after_recovery).to be_nil
        expect(command).to have_received(:current_job_status).exactly(statuses.length).times
        expect(Time).to have_received(:now).twice
        expect(Shell).not_to have_received(:warn)
      end
    end

    it "keeps a bounded status outage provisional while logs are quiet" do
      now = 0.0
      unavailable_streak = Array.new(described_class::JOB_STATUS_UNAVAILABLE_RETRY_LIMIT + 1)
      statuses = [*unavailable_streak, "successful"]

      allow(command).to receive(:print_uniq_logs).and_return(:unchanged, :finished)
      allow(command).to receive(:current_job_status).and_return(*statuses)
      allow(command).to receive(:monotonic_time) { now }
      allow(command).to receive(:sleep) { |duration| now += duration }
      allow(Kernel).to receive(:sleep) { |duration| now += duration }

      result = command.send(:show_logs_waiting)

      expect(result).to eq(ExitCode::SUCCESS)
      expect(command).to have_received(:print_uniq_logs).twice
      expect(command).to have_received(:current_job_status).exactly(statuses.length).times
      expect(command).not_to have_received(:sleep)
      expect(Kernel).to have_received(:sleep).with(1).exactly(unavailable_streak.length).times
    end

    it "reconciles a finish marker that arrives after the unavailable threshold" do
      now = 0.0
      unavailable_streak = Array.new(described_class::JOB_STATUS_UNAVAILABLE_RETRY_LIMIT + 1)
      statuses = [*unavailable_streak, nil, "successful"]

      allow(command).to receive(:print_uniq_logs)
        .and_return(*Array.new(unavailable_streak.length, :changed), :finished)
      allow(command).to receive(:current_job_status).and_return(*statuses)
      allow(command).to receive(:monotonic_time) { now }
      allow(Kernel).to receive(:sleep) { |duration| now += duration }

      result = command.send(:show_logs_waiting)

      expect(result).to eq(ExitCode::SUCCESS)
      expect(command).to have_received(:current_job_status).exactly(statuses.length).times
      expect(command).to have_received(:print_uniq_logs).exactly(unavailable_streak.length + 1).times
      expect(Kernel).to have_received(:sleep).with(1).exactly(statuses.length - 1).times
    end

    it "lets an authoritative failure override a finished log marker" do
      now = 0.0
      unavailable_streak = Array.new(described_class::JOB_STATUS_UNAVAILABLE_RETRY_LIMIT + 1)
      statuses = [*unavailable_streak, "failed"]

      allow(command).to receive(:print_uniq_logs).and_return(:finished)
      allow(command).to receive(:current_job_status).and_return(*statuses)
      allow(command).to receive(:monotonic_time) { now }
      allow(Kernel).to receive(:sleep) { |duration| now += duration }
      allow(Shell).to receive(:warn)

      result = command.send(:show_logs_waiting)

      expect(result).to eq(ExitCode::ERROR_DEFAULT)
      expect(command).to have_received(:current_job_status).exactly(statuses.length).times
      expect(Shell).not_to have_received(:warn)
    end

    it "returns an error at the fixed deadline when status stays unavailable after the finish marker" do
      now = 0.0
      warning = nil
      unsafe_diagnostics = {
        raw_response: "raw-response-detail",
        command: "command-detail",
        environment: "environment-detail",
        token: "credential-detail"
      }
      unsafe_diagnostics.each { |name, value| command.instance_variable_set(:"@#{name}", value) }

      allow(command).to receive_messages(print_uniq_logs: :finished, current_job_status: nil)
      allow(command).to receive(:monotonic_time) { now }
      allow(command).to receive(:sleep) { |duration| now += duration }
      allow(Kernel).to receive(:sleep) { |duration| now += duration }
      allow(Shell).to receive(:warn) { |message| warning = message }

      result = command.send(:show_logs_waiting)

      expect(result).to eq(ExitCode::ERROR_DEFAULT)
      expect(now).to eq(described_class::POST_TERMINAL_LOG_DRAIN_SECONDS)
      expect(command).to have_received(:print_uniq_logs).once
      expect(warning).to eq(
        "Runner job status reconciliation reached the 120-second deadline " \
        "(last_status: unavailable); returning exit status 64."
      )
      expect(Shell).to have_received(:warn).once
      unsafe_diagnostics.each_value { |value| expect(warning).not_to include(value) }
    end

    it "caps provisional polling at the fixed monotonic deadline" do
      now = 0.0

      allow(command).to receive(:print_uniq_logs).and_return(:finished)
      allow(command).to receive(:current_job_status) do
        now = described_class::POST_TERMINAL_LOG_DRAIN_SECONDS - 0.25
        nil
      end
      allow(command).to receive(:monotonic_time) { now }
      allow(Kernel).to receive(:sleep) { |duration| now += duration }
      allow(Shell).to receive(:warn)

      result = command.send(:show_logs_waiting)

      expect(result).to eq(ExitCode::ERROR_DEFAULT)
      expect(now).to eq(described_class::POST_TERMINAL_LOG_DRAIN_SECONDS)
      expect(Kernel).to have_received(:sleep).with(0.25).once
      expect(Shell).to have_received(:warn).once
    end

    it "does not start a status request after a log request crosses the reconciliation deadline" do
      now = 0.0
      log_requests = 0
      deadline = described_class::JOB_STATUS_UNAVAILABLE_RETRY_LIMIT +
                 described_class::POST_TERMINAL_LOG_DRAIN_SECONDS

      allow(command).to receive(:print_uniq_logs) do
        log_requests += 1
        if log_requests > described_class::JOB_STATUS_UNAVAILABLE_RETRY_LIMIT + 1
          now = deadline + 1
          :finished
        else
          :changed
        end
      end
      allow(command).to receive(:current_job_status).and_return(nil)
      allow(command).to receive(:monotonic_time) { now }
      allow(Kernel).to receive(:sleep) { |duration| now += duration }
      allow(Shell).to receive(:warn)

      result = command.send(:show_logs_waiting)

      expect(result).to eq(ExitCode::ERROR_DEFAULT)
      expect(command).to have_received(:print_uniq_logs)
        .exactly(described_class::JOB_STATUS_UNAVAILABLE_RETRY_LIMIT + 2).times
      expect(command).to have_received(:current_job_status)
        .exactly(described_class::JOB_STATUS_UNAVAILABLE_RETRY_LIMIT + 1).times
      expect(Shell).to have_received(:warn).once
    end

    %w[active pending].each do |nonterminal_status|
      it "does not clear an outage deadline after a finish marker and #{nonterminal_status} status" do
        now = 0.0
        status_index = 0
        last_status = nil
        unavailable_threshold = Array.new(described_class::JOB_STATUS_UNAVAILABLE_RETRY_LIMIT + 1)
        statuses = [*unavailable_threshold, nonterminal_status, "successful"]
        expected_deadline = described_class::JOB_STATUS_UNAVAILABLE_RETRY_LIMIT +
                            described_class::POST_TERMINAL_LOG_DRAIN_SECONDS

        allow(command).to receive(:print_uniq_logs)
          .and_return(*Array.new(unavailable_threshold.length, :changed), :finished)
        allow(command).to receive(:current_job_status) do
          last_status = statuses[status_index]
          status_index += 1
          last_status
        end
        allow(command).to receive(:monotonic_time) { now }
        allow(Kernel).to receive(:sleep) do |duration|
          now = last_status == nonterminal_status ? expected_deadline : now + duration
        end
        allow(Shell).to receive(:warn)

        result = command.send(:show_logs_waiting)

        expect(result).to eq(ExitCode::ERROR_DEFAULT)
        expect(now).to eq(expected_deadline)
        expect(command).to have_received(:print_uniq_logs).exactly(unavailable_threshold.length + 1).times
        expect(command).to have_received(:current_job_status).exactly(unavailable_threshold.length + 1).times
        expect(Shell).to have_received(:warn).with(
          "Runner job status reconciliation reached the 120-second deadline " \
          "(last_status: #{nonterminal_status}); returning exit status 64."
        ).once
      end
    end

    it "normalizes an unsafe status before writing the verbose diagnostic" do
      now = 0.0
      unsafe_status = "failed\nraw-response-detail"
      allow(command).to receive(:print_uniq_logs).and_return(:changed, :finished)
      allow(command).to receive(:current_job_status).and_return(unsafe_status)
      allow(command).to receive(:monotonic_time) { now }
      allow(Kernel).to receive(:sleep) { |duration| now += duration }
      allow(Shell).to receive(:debug)

      result = command.send(:show_logs_waiting)

      expect(result).to eq(ExitCode::ERROR_DEFAULT)
      expect(command).to have_received(:current_job_status).once
      expect(Shell).to have_received(:debug).with("JOB STATUS", "unknown").once
      expect(Shell).not_to have_received(:debug).with("JOB STATUS", unsafe_status)
    end

    it "keeps an unavailable cron status fail-closed in the blocking resolver" do
      allow(command).to receive(:current_job_status).and_return(nil)

      result = command.send(:resolve_job_status)

      expect(result).to eq(ExitCode::ERROR_DEFAULT)
      expect(command).to have_received(:current_job_status).once
    end

    it "honors a finished result from a log request that crosses the deadline" do
      now = 0.0
      log_requests = 0

      allow(command).to receive(:print_uniq_logs) do
        log_requests += 1
        if log_requests == 1
          :unchanged
        else
          now = described_class::POST_TERMINAL_LOG_DRAIN_SECONDS + 1.0
          :finished
        end
      end
      allow(command).to receive(:current_job_status).and_return("successful")
      allow(command).to receive(:monotonic_time) { now }
      allow(Kernel).to receive(:sleep) { now = described_class::POST_TERMINAL_LOG_DRAIN_SECONDS - 1.0 }

      result = command.send(:show_logs_waiting)

      expect(result).to eq(ExitCode::SUCCESS)
      expect(command).to have_received(:print_uniq_logs).twice
      expect(command).to have_received(:current_job_status).once
    end

    it "preserves the terminal status and deadline across a transient log error" do
      now = 0.0
      log_requests = 0

      allow(command).to receive(:print_uniq_logs) do
        log_requests += 1
        case log_requests
        when 1
          :changed
        when 2
          now = described_class::POST_TERMINAL_LOG_DRAIN_SECONDS + 1.0
          raise "temporary log API failure"
        else
          :finished
        end
      end
      allow(command).to receive_messages(
        current_job_status: "failed",
        resolve_job_status: ExitCode::ERROR_DEFAULT,
        progress: progress
      )
      allow(command).to receive(:monotonic_time) { now }
      allow(Kernel).to receive(:sleep) { |duration| now += duration }

      result = command.send(:show_logs_waiting)

      expect(result).to eq(ExitCode::ERROR_DEFAULT)
      expect(command).to have_received(:print_uniq_logs).twice
      expect(command).to have_received(:current_job_status).once
      expect(command).not_to have_received(:resolve_job_status)
      expect(Kernel).to have_received(:sleep).with(1).once
    end
  end

  describe "#print_uniq_logs" do
    let(:command) { described_class.allocate }
    let(:cp) { instance_double(Controlplane) }
    let(:progress) { instance_double(IO, puts: nil) }

    it "keeps the post-terminal query boundary pinned while delayed entries become visible" do
      query_from = 1_788_000_000
      output_timestamp = "#{query_from + 10}000000000"
      marker_timestamp = "#{query_from + 10}000000001"
      empty_log = { "data" => { "result" => [] } }
      delayed_log = {
        "data" => {
          "result" => [{
            "values" => [
              [output_timestamp, "Gemfile"],
              [marker_timestamp, described_class::MAGIC_END]
            ]
          }]
        }
      }

      allow(command).to receive_messages(cp: cp, progress: progress)
      allow(cp).to receive(:log_get).and_return(empty_log, delayed_log)
      allow(Time).to receive(:now).and_return(Time.at(query_from + 60), Time.at(query_from + 121))
      command.instance_variable_set(:@runner_workload, "rails-runner")
      command.instance_variable_set(:@replica, "rails-runner-replica")
      command.instance_variable_set(:@post_terminal_log_from, query_from)

      expect(command.send(:print_uniq_logs)).to eq(:unchanged)
      expect(command.send(:print_uniq_logs)).to eq(:finished)
      expect(cp).to have_received(:log_get).with(
        workload: "rails-runner", from: query_from, to: query_from + 60, replica: "rails-runner-replica"
      ).ordered
      expect(cp).to have_received(:log_get).with(
        workload: "rails-runner", from: query_from, to: query_from + 121, replica: "rails-runner-replica"
      ).ordered
      expect(progress).to have_received(:puts).with("Gemfile")
      expect(progress).not_to have_received(:puts).with(described_class::MAGIC_END)
    end

    it "recognizes and strips a finish marker appended to unterminated output" do
      timestamp = "1788000010000000000"
      appended_marker_log = {
        "data" => {
          "result" => [{
            "values" => [[timestamp, "done#{described_class::MAGIC_END}"]]
          }]
        }
      }

      allow(command).to receive_messages(cp: cp, progress: progress)
      allow(cp).to receive(:log_get).and_return(appended_marker_log)
      allow(Time).to receive(:now).and_return(Time.at(1_788_000_020))
      command.instance_variable_set(:@runner_workload, "rails-runner")
      command.instance_variable_set(:@replica, "rails-runner-replica")

      expect(command.send(:print_uniq_logs)).to eq(:finished)
      expect(progress).to have_received(:puts).with("done")
      expect(progress).not_to have_received(:puts).with(include(described_class::MAGIC_END))
    end
  end

  describe "#wait_for_replica_for_job" do
    let(:config) { instance_double(Config) }
    let(:cp) { instance_double(Controlplane) }
    let(:progress) { StringIO.new }
    let(:command) { described_class.new(config) }

    before do
      allow(command).to receive_messages(cp: cp)
      allow(command).to receive(:step) { |_message, **_options, &block| block.call }

      command.instance_variable_set(:@runner_workload, "rails-runner")
      command.instance_variable_set(:@job, "job-123")
      command.instance_variable_set(:@job_timeout, described_class::DEFAULT_JOB_TIMEOUT)
      command.instance_variable_set(:@location, "aws-us-east-2")
    end

    it "returns as soon as a replica for the job is observed" do
      allow(cp).to receive(:fetch_workload_replicas)
        .with("rails-runner", location: "aws-us-east-2")
        .and_return({ "items" => ["rails-runner-job-123-replica"] })
      allow(cp).to receive(:fetch_cron_workload)

      result = command.send(:wait_for_replica_for_job)

      expect(result).to eq("rails-runner-job-123-replica")
      expect(command.instance_variable_get(:@replica)).to eq("rails-runner-job-123-replica")
      expect(cp).not_to have_received(:fetch_cron_workload)
    end

    it "prints one progress dot for each unsuccessful observation" do
      now = 0.0
      replica_responses = [
        { "items" => [] },
        { "items" => [] },
        { "items" => ["rails-runner-job-123-replica"] }
      ]

      command.instance_variable_set(:@job_timeout, 5)
      allow(command).to receive(:step).and_call_original
      allow(command).to receive(:progress).and_return(progress)
      allow(progress).to receive(:print).and_call_original
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { now }
      allow(Kernel).to receive(:sleep) { |duration| now += duration }
      allow(cp).to receive(:fetch_workload_replicas)
        .with("rails-runner", location: "aws-us-east-2")
        .and_return(*replica_responses)
      allow(cp).to receive(:fetch_cron_workload)
        .with("rails-runner", location: "aws-us-east-2")
        .and_return({ "items" => [{ "id" => "job-123", "status" => "active" }] })

      command.send(:wait_for_replica_for_job)

      expect(command.instance_variable_get(:@replica)).to eq("rails-runner-job-123-replica")
      expect(progress).to have_received(:print).with(".").twice
      expect(Kernel).to have_received(:sleep).with(1).twice
    end

    it "fails immediately with the terminal cron status when no replica was observed" do
      allow(command).to receive(:step).and_call_original
      allow(command).to receive(:progress).and_return(progress)
      allow(cp).to receive(:fetch_workload_replicas)
        .with("rails-runner", location: "aws-us-east-2")
        .and_return({ "items" => [] })
      allow(cp).to receive(:fetch_cron_workload)
        .with("rails-runner", location: "aws-us-east-2")
        .and_return({ "items" => [{ "id" => "job-123", "status" => "failed" }] })

      expect { command.send(:wait_for_replica_for_job) }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(ExitCode::ERROR_DEFAULT)
      end

      expect(progress.string).to include("status: failed")
      expect(cp).to have_received(:fetch_workload_replicas).once
      expect(cp).to have_received(:fetch_cron_workload).once
    end

    it "replaces an unsafe terminal cron status instead of printing it" do
      unsafe_status = "failed\nunsafe-status-details"

      allow(command).to receive(:step).and_call_original
      allow(command).to receive(:progress).and_return(progress)
      allow(cp).to receive(:fetch_workload_replicas)
        .with("rails-runner", location: "aws-us-east-2")
        .and_return({ "items" => [] })
      allow(cp).to receive(:fetch_cron_workload)
        .with("rails-runner", location: "aws-us-east-2")
        .and_return({ "items" => [{ "id" => "job-123", "status" => unsafe_status }] })

      expect { command.send(:wait_for_replica_for_job) }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(ExitCode::ERROR_DEFAULT)
      end

      expect(progress.string).to include("status: unknown")
      expect(progress.string).not_to include(unsafe_status)
    end

    it "does not start a cron-status request after the replica request reaches the deadline" do
      now = 0.0

      command.instance_variable_set(:@job_timeout, 0.25)
      allow(command).to receive(:step).and_call_original
      allow(command).to receive(:progress).and_return(progress)
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { now }
      allow(Kernel).to receive(:sleep)
      allow(cp).to receive(:fetch_workload_replicas)
        .with("rails-runner", location: "aws-us-east-2") do
          now = 0.3
          { "items" => [] }
        end
      allow(cp).to receive(:fetch_cron_workload)
        .with("rails-runner", location: "aws-us-east-2")
        .and_return({ "items" => [{ "id" => "job-123", "status" => "active" }] })

      expect { command.send(:wait_for_replica_for_job) }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(ExitCode::ERROR_DEFAULT)
      end

      expect(progress.string).to include("observation limit: 0.25 seconds", "status: unavailable")
      expect(cp).not_to have_received(:fetch_cron_workload)
      expect(Kernel).not_to have_received(:sleep)
    end

    it "caps the observation limit at 1000 seconds when the runner job timeout is higher" do
      now = 0.0

      command.instance_variable_set(:@job_timeout, 2_000)
      allow(command).to receive(:step).and_call_original
      allow(command).to receive(:progress).and_return(progress)
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { now }
      allow(cp).to receive(:fetch_workload_replicas)
        .with("rails-runner", location: "aws-us-east-2") do
          now = 1_001.0
          { "items" => [] }
        end
      allow(cp).to receive(:fetch_cron_workload)

      expect { command.send(:wait_for_replica_for_job) }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(ExitCode::ERROR_DEFAULT)
      end

      expect(progress.string).to include("observation limit: 1000 seconds", "status: unavailable")
      expect(cp).not_to have_received(:fetch_cron_workload)
    end

    [nil, "active", "pending"].each do |status|
      it "stops polling at the monotonic deadline when the cron status is #{status || 'unavailable'}" do
        now = 0.0
        sleeps = []
        expected_status = status || "unavailable"
        job_items = status ? [{ "id" => "job-123", "status" => status }] : []

        command.instance_variable_set(:@job_timeout, 0.25)
        allow(command).to receive(:step).and_call_original
        allow(command).to receive(:progress).and_return(progress)
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { now }
        allow(Kernel).to receive(:sleep) do |duration|
          sleeps << duration
          now += duration
        end
        allow(cp).to receive(:fetch_workload_replicas)
          .with("rails-runner", location: "aws-us-east-2")
          .and_return({ "items" => [] })
        allow(cp).to receive(:fetch_cron_workload)
          .with("rails-runner", location: "aws-us-east-2")
          .and_return({ "items" => job_items })

        expect { command.send(:wait_for_replica_for_job) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(ExitCode::ERROR_DEFAULT)
        end

        expect(progress.string).to include("observation limit: 0.25 seconds", "status: #{expected_status}")
        expect(sleeps).to eq([0.25])
        expect(cp).to have_received(:fetch_workload_replicas).once
        expect(cp).to have_received(:fetch_cron_workload).once
      end
    end

    it "stops waiting when the cron job finishes before a replica is observed" do
      allow(cp).to receive(:fetch_workload_replicas)
        .with("rails-runner", location: "aws-us-east-2")
        .and_return({ "items" => [] })
      allow(cp).to receive(:fetch_cron_workload)
        .with("rails-runner", location: "aws-us-east-2")
        .and_return({ "items" => [{ "id" => "job-123", "status" => "successful" }] })

      result = command.send(:wait_for_replica_for_job)

      expect(result).to be(true)
      expect(command.instance_variable_get(:@replica)).to be_nil
      expect(command.instance_variable_get(:@job_completed_before_replica_exit_status)).to eq(ExitCode::SUCCESS)
    end
  end
end
