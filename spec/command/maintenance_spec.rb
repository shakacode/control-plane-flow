# frozen_string_literal: true

require "spec_helper"

describe Command::Maintenance do
  include_examples "validates domain existence", command: "maintenance"

  context "when app has domain" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    before do
      allow(Kernel).to receive(:sleep)

      run_cpflow_command!("ps:start", "-a", app, "--wait")
    end

    it "displays 'off' if maintenance mode is disabled", :slow do
      run_cpflow_command!("maintenance:off", "-a", app)
      result = run_cpflow_command("maintenance", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("off")
    end

    it "displays 'on' if maintenance mode is enabled", :slow do
      run_cpflow_command!("maintenance:on", "-a", app)
      result = run_cpflow_command("maintenance", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("on")
    end
  end
end
