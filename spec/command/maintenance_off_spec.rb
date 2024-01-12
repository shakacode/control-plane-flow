# frozen_string_literal: true

require "spec_helper"

describe Command::MaintenanceOff do
  context "when app has no domain" do
    let!(:app) { dummy_test_app("with-nothing") }

    it "raises error", :fast do
      result = run_cpl_command("maintenance:off", "-a", app)

      expect(result[:status]).to eq(1)
      expect(result[:stderr]).to include("Can't find domain")
    end
  end

  context "when maintenance workload does not exist" do
    let!(:app) { dummy_test_app("default", create_if_not_exists: true) }

    it "raises error", :fast do
      result = run_cpl_command("maintenance:off", "-a", app)

      expect(result[:status]).to eq(1)
      expect(result[:stderr]).to include("Can't find workload 'maintenance'")
    end
  end

  context "when maintenance workload exists" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    before do
      allow(Kernel).to receive(:sleep)

      run_cpl_command!("ps:start", "-a", app, "--wait")
    end

    it "does nothing if maintenance mode is already disabled", :slow do
      run_cpl_command!("maintenance:off", "-a", app)
      result = run_cpl_command("maintenance:off", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Maintenance mode is already disabled for app '#{app}'")
    end

    it "disables maintenance mode", :slow do
      run_cpl_command!("maintenance:on", "-a", app)
      result = run_cpl_command("maintenance:off", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Maintenance mode disabled for app '#{app}'")
    end
  end
end
