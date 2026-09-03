# frozen_string_literal: true

require "spec_helper"
require "shellwords"

describe Controlplane do
  describe "#initialize" do
    let!(:fake_config) { Struct.new(:app, :org).new("my-app", "my-org") }

    it "raises error if org does not exist" do
      allow_any_instance_of(ControlplaneApi).to receive(:list_orgs).and_return({ "items" => [] }) # rubocop:disable RSpec/AnyInstance

      expect do
        described_class.new(fake_config)
      end.to raise_error(include("Can't find org 'my-org'"))
    end

    it "allows scoped tokens that cannot list orgs to continue to the target API call" do
      allow_any_instance_of(ControlplaneApi).to receive(:list_orgs).and_return(nil) # rubocop:disable RSpec/AnyInstance

      expect { described_class.new(fake_config) }.not_to raise_error
    end

    it "allows scoped tokens that are forbidden from listing orgs to continue to the target API call" do
      response = instance_double(Net::HTTPForbidden, body: '{"message":"forbidden"}', to_s: "403 Forbidden")
      error = ControlplaneApiDirect::ForbiddenError.new(url: "/org", response: response)
      allow_any_instance_of(ControlplaneApi).to receive(:list_orgs).and_raise(error) # rubocop:disable RSpec/AnyInstance

      expect { described_class.new(fake_config) }.not_to raise_error
    end
  end

  describe "#workload_exec" do
    let(:described_instance) do
      described_class.allocate.tap do |instance|
        instance.instance_variable_set(:@gvc, "my app")
        instance.instance_variable_set(:@org, "my org")
      end
    end
    let(:process_status) { instance_double(Process::Status, exited?: true, success?: true) }

    before do
      allow(Process).to receive(:spawn).and_return(1234)
      allow(Process).to receive(:wait2).with(1234).and_return([1234, process_status])
    end

    it "spawns local cpln command arguments without shell interpolation" do
      command = ["bash", "-c", 'eval "$CPFLOW_RUNNER_SCRIPT"']

      result = described_instance.workload_exec(
        "rails runner", "replica;id", location: "location $HOME", container: "rails`id`", command: command
      )

      expect(result).to be(true)
      expect(Process).to have_received(:spawn).with(
        "cpln", "workload", "exec", "rails runner",
        "--gvc", "my app", "--org", "my org",
        "--replica", "replica;id", "--location", "location $HOME", "-it",
        "--container", "rails`id`", "--",
        "bash", "-c", 'eval "$CPFLOW_RUNNER_SCRIPT"'
      )
    end
  end

  describe "#kernel_system_with_pid_handling" do
    let(:described_instance) { described_class.allocate }
    let(:process_status) { instance_double(Process::Status, exited?: true, success?: true) }

    before do
      allow(Process).to receive(:spawn).and_return(1234)
      allow(Process).to receive(:wait2).with(1234).and_return([1234, process_status])
    end

    it "passes capture options to an argv-safe process spawn" do
      output = instance_double(IO)

      result = described_instance.send(
        :kernel_system_with_pid_handling,
        ["cpln", "workload", "update", "rails runner"],
        out: output,
        err: %i[child out]
      )

      expect(result).to be(true)
      expect(Process).to have_received(:spawn).with(
        "cpln", "workload", "update", "rails runner",
        out: output,
        err: %i[child out]
      )
    end
  end

  describe "#build_command" do
    let!(:fake_config) { Struct.new(:app, :org).new("my-app", nil) }
    let!(:described_instance) { described_class.new(fake_config) }
    let!(:original_cmd) { "cmd" }

    before do
      stub_env("HIDE_COMMAND_OUTPUT", nil)
      allow(Shell).to receive(:should_hide_output?).and_return(false)
    end

    it "does not hide anything by default" do
      cmd = described_instance.send(:build_command, original_cmd)

      expect(cmd).to eq(original_cmd)
    end

    it "does not hide anything when 'output_mode' is :all" do
      cmd = described_instance.send(:build_command, original_cmd, output_mode: :all)

      expect(cmd).to eq(original_cmd)
    end

    it "hides stdout when 'output_mode' is :errors_only" do
      cmd = described_instance.send(:build_command, original_cmd, output_mode: :errors_only)

      expect(cmd).to eq("#{original_cmd} > /dev/null")
    end

    it "hides everything when 'output_mode' is :none" do
      cmd = described_instance.send(:build_command, original_cmd, output_mode: :none)

      expect(cmd).to eq("#{original_cmd} > /dev/null 2>&1")
    end

    it "hides everything when 'HIDE_COMMAND_OUTPUT' env var is set to 'true'" do
      stub_env("HIDE_COMMAND_OUTPUT", "true")

      cmd = described_instance.send(:build_command, original_cmd)

      expect(cmd).to eq("#{original_cmd} > /dev/null 2>&1")
    end

    it "provided 'output_mode' overrides 'HIDE_COMMAND_OUTPUT' env var" do
      stub_env("HIDE_COMMAND_OUTPUT", "true")

      cmd = described_instance.send(:build_command, original_cmd, output_mode: :all)

      expect(cmd).to eq(original_cmd)
    end

    it "hides stdout when 'Shell.should_hide_output?' is true" do
      allow(Shell).to receive(:should_hide_output?).and_return(true)

      cmd = described_instance.send(:build_command, original_cmd)

      expect(cmd).to eq("#{original_cmd} > /dev/null")
    end

    it "raises error when 'output_mode' is invalid" do
      expect do
        described_instance.send(:build_command, original_cmd, output_mode: :invalid)
      end.to raise_error("Invalid command output mode 'invalid'.")
    end

    it "rejects output suppression for array commands" do
      expect do
        described_instance.send(:build_command, ["cmd", "two words"], output_mode: :errors_only)
      end.to raise_error("Array commands require output mode 'all'.")
    end
  end

  describe "#fetch_workload_with_status" do
    let(:described_instance) do
      described_class.allocate.tap do |instance|
        instance.instance_variable_set(:@gvc, "my-app")
        instance.instance_variable_set(:@org, "my-org")
      end
    end

    it "returns the workload with computed status from the CLI" do
      workload = { "name" => "rails", "status" => { "readyLatest" => true } }
      allow(Shell).to receive(:cmd).with(
        "cpln", "workload", "get", "rails",
        "--gvc", "my-app", "--org", "my-org", "-o", "json",
        separate_stderr: true
      ).and_return({ success: true, output: JSON.generate(workload), error_output: "update available" })

      expect(described_instance.fetch_workload_with_status("rails")).to eq(workload)
    end

    it "warns and returns nil when the CLI lookup fails" do
      allow(Shell).to receive(:cmd).and_return({ success: false, output: "", error_output: "not authorized" })
      allow(Shell).to receive(:warn)

      expect(described_instance.fetch_workload_with_status("rails")).to be_nil
      expect(Shell).to have_received(:warn).with(
        "Failed to fetch status for 'rails': not authorized"
      )
    end

    it "warns and returns nil when the CLI output is not JSON" do
      allow(Shell).to receive(:cmd).and_return({ success: true, output: "not json", error_output: "" })
      allow(Shell).to receive(:warn)

      expect(described_instance.fetch_workload_with_status("rails")).to be_nil
      expect(Shell).to have_received(:warn).with(
        a_string_starting_with("Failed to parse status for 'rails':")
      )
    end
  end

  describe "#set_workload_suspend" do
    let(:api) { instance_double(ControlplaneApi) }
    let(:described_instance) do
      described_class.allocate.tap do |instance|
        instance.instance_variable_set(:@gvc, "prefix")
        instance.instance_variable_set(:@org, "my-org")
        instance.instance_variable_set(:@api, api)
      end
    end
    let(:workload_data) do
      { "spec" => { "defaultOptions" => { "suspend" => false } } }
    end

    it "targets an explicitly selected GVC for stale-app cleanup" do
      allow(api).to receive(:workload_get)
        .with(org: "my-org", gvc: "matched-stale-app", workload: "postgres")
        .and_return(workload_data)
      allow(api).to receive(:update_workload)

      expect(described_instance.set_workload_suspend("postgres", true, "matched-stale-app")).to be_nil

      expect(api).to have_received(:update_workload).with(
        org: "my-org",
        gvc: "matched-stale-app",
        workload: "postgres",
        data: { "spec" => { "defaultOptions" => { "suspend" => true } } }
      )
    end

    it "treats a missing workload as already suspended when requested" do
      allow(api).to receive(:workload_get)
        .with(org: "my-org", gvc: "matched-stale-app", workload: "postgres")
        .and_return(nil)
      allow(api).to receive(:update_workload)

      expect(
        described_instance.set_workload_suspend("postgres", true, "matched-stale-app", missing_ok: true)
      ).to be(true)
      expect(api).not_to have_received(:update_workload)
    end

    it "still raises for a missing workload by default" do
      allow(api).to receive(:workload_get)
        .with(org: "my-org", gvc: "matched-stale-app", workload: "postgres")
        .and_return(nil)

      expect do
        described_instance.set_workload_suspend("postgres", true, "matched-stale-app")
      end.to raise_error("Can't find workload 'postgres', " \
                         "please create it with 'cpflow apply-template postgres -a matched-stale-app'.")
    end

    it "treats a workload deleted during the suspend update as already suspended when requested" do
      allow(api).to receive(:workload_get)
        .with(org: "my-org", gvc: "matched-stale-app", workload: "postgres")
        .and_return(workload_data)
      allow(api).to receive(:update_workload).and_return(nil)

      expect(
        described_instance.set_workload_suspend("postgres", true, "matched-stale-app", missing_ok: true)
      ).to be(true)
    end
  end

  describe "#image_build" do
    let!(:fake_config) { Struct.new(:app, :org).new("my-app", nil) }
    let!(:described_instance) { described_class.new(fake_config) }

    it "shell-escapes Docker build tokens before spawning the command" do
      allow(described_instance).to receive(:perform!)

      described_instance.image_build(
        "example.registry.cpln.io/my-app:1",
        dockerfile: ".controlplane/Dockerfile",
        docker_context: ".",
        docker_args: ["--build-arg=PAYLOAD=$(touch${IFS}/tmp/pwned)"],
        build_args: ["GIT_COMMIT=abc123"]
      )

      expect(described_instance).to have_received(:perform!) do |cmd|
        expect(cmd).not_to include("$(touch")
        expect(Shellwords.split(cmd)).to eq(
          [
            "docker", "build", "--platform=linux/amd64",
            "-t", "example.registry.cpln.io/my-app:1",
            "-f", ".controlplane/Dockerfile",
            "--build-arg=PAYLOAD=$(touch${IFS}/tmp/pwned)",
            "--build-arg", "GIT_COMMIT=abc123",
            "."
          ]
        )
      end
    end
  end

  describe "#workload_set_image_ref" do
    let(:fake_config) { Struct.new(:app, :org).new("my-app", "my-org") }
    let(:described_instance) { described_class.new(fake_config) }

    before do
      allow_any_instance_of(ControlplaneApi).to receive(:list_orgs).and_return({ "items" => [{ "name" => "my-org" }] }) # rubocop:disable RSpec/AnyInstance
      allow(described_instance).to receive(:perform_with_output).and_call_original
      allow(described_instance).to receive(:perform_with_output)
        .with(
          "cpln workload update rails --gvc my-app --org my-org " \
          "--set spec.containers.web.image=/org/my-org/image/my-app:2"
        )
        .and_return({ success: false, output: "409 Conflict" })
    end

    it "returns the captured command result so the caller can classify the failure" do
      result = described_instance.workload_set_image_ref(
        "rails",
        container: "web",
        image: "my-app:2"
      )

      expect(result).to eq(success: false, output: "409 Conflict")
    end

    it "tracks the captured subprocess until it exits" do
      process_status = instance_double(Process::Status, exited?: true, success?: false)
      allow(Process).to receive(:spawn).and_return(12_345)
      allow(Process).to receive(:wait2).with(12_345) do
        expect($child_pids).to include(12_345) # rubocop:disable Style/GlobalVars
        [12_345, process_status]
      end

      result = described_instance.send(:perform_with_output, "cpln workload update")

      expect(result).to eq(success: false, output: "")
      expect(Process).to have_received(:spawn).with(
        "cpln workload update",
        out: an_instance_of(IO),
        err: %i[child out]
      )
      expect($child_pids).not_to include(12_345) # rubocop:disable Style/GlobalVars
    end

    it "streams output while capturing it when command output is visible" do
      stub_env("HIDE_COMMAND_OUTPUT", "false")
      Shell.verbose_mode(true)

      result = nil
      expect do
        result = described_instance.send(:perform_with_output, "printf 'live output'")
      end.to output("live output").to_stdout

      expect(result).to eq(success: true, output: "live output")
    ensure
      Shell.verbose_mode(false)
    end

    it "captures output without streaming it when command output is hidden" do
      stub_env("HIDE_COMMAND_OUTPUT", "true")

      result = nil
      expect do
        result = described_instance.send(:perform_with_output, "printf 'hidden output'")
      end.not_to output.to_stdout

      expect(result).to eq(success: true, output: "hidden output")
    end
  end
end
