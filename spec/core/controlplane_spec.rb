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
end
