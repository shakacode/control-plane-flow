# frozen_string_literal: true

require "spec_helper"

describe DummyAppSetup do
  describe ".cleanup" do
    let(:apps) { %w[dummy-test-valid-pre-deletion-hook-bbbb-cccc dummy-test-full-bbbb] }

    around do |example|
      registered = CommandHelpers.apps_to_delete.dup
      example.run
      CommandHelpers.apps_to_delete.replace(registered)
    end

    before do
      allow(CommandHelpers).to receive(:run_cpflow_command)
      allow(CommandHelpers).to receive(:delete_config_file)
      CommandHelpers.apps_to_delete.replace(apps)
    end

    it "deletes every registered app" do
      described_class.cleanup

      apps.each do |app|
        expect(CommandHelpers).to have_received(:run_cpflow_command).with("delete", "-a", app, "--yes")
      end
    end
  end
end
