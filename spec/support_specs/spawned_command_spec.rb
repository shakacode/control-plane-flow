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
    it "polls nonblockingly without asynchronous timeout exceptions" do
      allow(Process).to receive(:clock_gettime)
        .with(Process::CLOCK_MONOTONIC)
        .and_return(10.0, 10.1)
      allow(Process).to receive(:wait)
        .with(12_345, Process::WNOHANG)
        .and_return(nil, 12_345)
      allow(Process).to receive(:kill)
      allow(Timeout).to receive(:timeout)

      command.wait

      expect(Process).to have_received(:wait)
        .with(12_345, Process::WNOHANG).twice
      expect(described_class::PROCESS_WAIT_POLL_INTERVAL_SECONDS).to be <= 0.1
      expect(Timeout).not_to have_received(:timeout)
      expect(Process).not_to have_received(:kill)
    end

    it "escalates from TERM to KILL when the process does not exit" do
      allow(Process).to receive(:clock_gettime)
        .with(Process::CLOCK_MONOTONIC)
        .and_return(10.0, 15.0, 20.0, 22.0, 30.0, 31.0)
      events = []
      allow(Process).to receive(:wait).with(12_345, Process::WNOHANG) do
        events << :wait
        nil
      end
      allow(Process).to receive(:kill) { |name, _pid| events << name }
      allow(Process).to receive(:detach).with(12_345) { events << :detach }

      command.wait

      expect(events).to eq([:wait, "TERM", :wait, "KILL", :wait, :detach])
    end

    it "treats an already-reaped child as exited" do
      allow(Process).to receive(:clock_gettime)
        .with(Process::CLOCK_MONOTONIC)
        .and_return(10.0)
      allow(Process).to receive(:wait)
        .with(12_345, Process::WNOHANG)
        .and_raise(Errno::ECHILD)
      allow(Process).to receive(:kill)

      command.wait

      expect(Process).not_to have_received(:kill)
    end

    it "continues cleanup when a process disappears before signaling" do
      allow(Process).to receive(:clock_gettime)
        .with(Process::CLOCK_MONOTONIC)
        .and_return(10.0, 15.0, 20.0, 22.0, 30.0, 31.0)
      allow(Process).to receive(:wait)
        .with(12_345, Process::WNOHANG)
        .and_return(nil)
      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)
      allow(Process).to receive(:detach).with(12_345)

      expect { command.wait }.not_to raise_error

      expect(Process).to have_received(:kill).with("TERM", 12_345).ordered
      expect(Process).to have_received(:kill).with("KILL", 12_345).ordered
      expect(Process).to have_received(:detach).with(12_345).ordered
    end
  end
end
