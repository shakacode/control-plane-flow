# frozen_string_literal: true

require "spec_helper"

describe Command::MaintenanceOn do
  context "when app has no domain" do
    let!(:app) { dummy_test_app("nothing") }

    it "raises error" do
      result = run_cpflow_command("maintenance:on", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find domain")
    end
  end

  context "when maintenance workload does not exist" do
    let!(:app) { dummy_test_app("default", create_if_not_exists: true) }

    it "raises error" do
      result = run_cpflow_command("maintenance:on", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find workload 'maintenance'")
    end
  end

  context "when maintenance workload exists" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    before do
      allow(Kernel).to receive(:sleep)

      run_cpflow_command!("ps:start", "-a", app, "--wait")
    end

    it "does nothing if maintenance mode is already enabled", :slow do
      run_cpflow_command!("maintenance:on", "-a", app)
      result = run_cpflow_command("maintenance:on", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Maintenance mode is already enabled for app '#{app}'")
    end

    it "enables maintenance mode", :slow do
      run_cpflow_command!("maintenance:off", "-a", app)
      result = run_cpflow_command("maintenance:on", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Maintenance mode enabled for app '#{app}'")
    end
  end
end
