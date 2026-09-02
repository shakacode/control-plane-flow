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
