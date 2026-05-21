# frozen_string_literal: true

require "spec_helper"

describe Command::Run do
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

        expect(progress).not_to have_received(:puts).with(/runner workload is still running/)
      end
    end

    context "when cpln workload exec exits with a non-zero status" do
      let(:exec_success) { false }

      it "prints a cleanup hint instead of aborting" do
        expect { command.send(:run_interactive) }.not_to raise_error

        expect(progress).to have_received(:puts).with(include("cpflow ps:stop"))
      end
    end
  end
end
