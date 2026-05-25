# frozen_string_literal: true

require "spec_helper"

describe Command::Run do
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
      command.instance_variable_set(:@command, %(bash -c 'true'))
      allow(cp).to receive(:workload_exec).and_return(exec_success)
    end

    context "when cpln workload exec exits successfully" do
      let(:exec_success) { true }

      it "does not print a cleanup hint" do
        command.send(:run_interactive)

        expect(cp).to have_received(:workload_exec).once
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
end
