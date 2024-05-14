# frozen_string_literal: true

require "spec_helper"

describe Controlplane do
  describe "#initialize" do
    let!(:fake_config) { Struct.new(:app, :org).new("my-app", "my-org") }

    it "raises error if org does not exist" do
      expect do
        described_class.new(fake_config)
      end.to raise_error(include("Can't find org 'my-org'"))
    end
  end

  describe "#build_command" do
    let!(:fake_config) { Struct.new(:app, :org).new("my-app", nil) }
    let!(:described_instance) { described_class.new(fake_config) }
    let!(:original_cmd) { "cmd" }

    before do
      allow(ENV).to receive(:fetch).with("HIDE_COMMAND_OUTPUT", nil).and_return(nil)
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
      allow(ENV).to receive(:fetch).with("HIDE_COMMAND_OUTPUT", nil).and_return("true")

      cmd = described_instance.send(:build_command, original_cmd)

      expect(cmd).to eq("#{original_cmd} > /dev/null 2>&1")
    end

    it "provided 'output_mode' overrides 'HIDE_COMMAND_OUTPUT' env var" do
      allow(ENV).to receive(:fetch).with("HIDE_COMMAND_OUTPUT", nil).and_return("true")

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
end
