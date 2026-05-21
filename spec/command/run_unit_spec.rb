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

    shared_examples "an aborted interactive session" do
      it "prints the cleanup hint instead of the generic error" do
        expect { command.send(:run_interactive) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(ExitCode::ERROR_DEFAULT)
        end

        expect(progress).to have_received(:puts).with(include("cpflow ps:stop"))
      end
    end

    context "when cpln workload exec exits with a non-zero status" do
      let(:exec_success) { false }

      it_behaves_like "an aborted interactive session"
    end

    context "when cpln workload exec is killed by a signal" do
      let(:exec_success) { nil }

      it_behaves_like "an aborted interactive session"
    end
  end
end
