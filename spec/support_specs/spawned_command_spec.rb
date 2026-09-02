# frozen_string_literal: true

require "spec_helper"

describe SpawnedCommand do
  subject(:command) { described_class.new(nil, nil, 12_345) }

  describe "#wait_for" do
    it "redacts matched sensitive output before writing it to the spec log" do
      sensitive_value = "opaque-upstream-token"
      output = instance_double(IO)
      command = described_class.new(
        output, nil, 12_345,
        sensitive_data_pattern: /#{Regexp.escape(sensitive_value)}/
      )
      allow(output).to receive(:expect).and_yield(["ready #{sensitive_value}"])

      Tempfile.create("cpflow-command-log") do |log_file|
        stub_const("LogHelpers::LOG_FILE", log_file.path)

        result = command.wait_for(/ready/)

        expect(result).to include(sensitive_value)
        expect(File.read(log_file.path)).to include("ready XXXXXXX")
        expect(File.read(log_file.path)).not_to include(sensitive_value)
      end
    end
  end

  describe "#wait" do
    it "returns without signaling when the process exits during the initial grace period" do
      allow(Timeout).to receive(:timeout).and_yield
      allow(Process).to receive(:wait).with(12_345).and_return(12_345)
      allow(Process).to receive(:kill)

      command.wait

      expect(Process).not_to have_received(:kill)
    end

    it "escalates from TERM to KILL when the process does not exit" do
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      allow(Process).to receive(:kill)
      allow(Process).to receive(:detach).with(12_345)

      command.wait

      expect(Timeout).to have_received(:timeout)
        .with(described_class::PROCESS_EXIT_GRACE_SECONDS).ordered
      expect(Process).to have_received(:kill).with("TERM", 12_345).ordered
      expect(Timeout).to have_received(:timeout)
        .with(described_class::PROCESS_TERM_GRACE_SECONDS).ordered
      expect(Process).to have_received(:kill).with("KILL", 12_345).ordered
      expect(Timeout).to have_received(:timeout)
        .with(described_class::PROCESS_KILL_GRACE_SECONDS).ordered
      expect(Process).to have_received(:detach).with(12_345).ordered
    end
  end
end
