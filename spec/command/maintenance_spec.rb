# frozen_string_literal: true

require "spec_helper"

describe Command::Maintenance do
  context "when app has no domain" do
    let!(:app) { dummy_test_app("with-nothing") }

    it "raises error" do
      result = run_cpl_command("maintenance", "-a", app)

      expect(result[:status]).to eq(1)
      expect(result[:stderr]).to include("Can't find domain")
    end
  end

  context "when app has domain" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    before do
      allow(Kernel).to receive(:sleep)

      run_cpl_command!("ps:start", "-a", app, "--wait")
    end

    it "displays 'off' if maintenance mode is disabled", :slow do
      run_cpl_command!("maintenance:off", "-a", app)
      result = run_cpl_command("maintenance", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("off")
    end

    it "displays 'on' if maintenance mode is enabled", :slow do
      run_cpl_command!("maintenance:on", "-a", app)
      result = run_cpl_command("maintenance", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("on")
    end
  end
end
