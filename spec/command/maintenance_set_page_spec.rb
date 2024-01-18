# frozen_string_literal: true

require "spec_helper"

describe Command::MaintenanceSetPage do
  let!(:example_maintenance_page) { "https://example.com/maintenance.html" }

  context "when maintenance workload does not exist" do
    let!(:app) { dummy_test_app("default", create_if_not_exists: true) }

    it "raises error", :fast do
      result = run_cpl_command("maintenance:set-page", example_maintenance_page, "-a", app)

      expect(result[:status]).to eq(1)
      expect(result[:stderr]).to include("Can't find workload 'maintenance'")
    end
  end

  context "when maintenance workload uses external (non-shakacode) image" do
    let!(:app) { dummy_test_app("with-external-maintenance-image") }

    before do
      run_cpl_command!("apply-template", "gvc", "maintenance-with-external-image", "-a", app)
    end

    after do
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "does nothing", :fast do
      result = run_cpl_command("maintenance:set-page", example_maintenance_page, "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).not_to include("Setting '#{example_maintenance_page}' as the page for maintenance mode")
    end
  end

  context "when maintenance workload uses shakacode image" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    it "sets page for maintenance mode", :fast do
      result = run_cpl_command("maintenance:set-page", example_maintenance_page, "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr])
        .to match(/Setting '#{example_maintenance_page}' as the page for maintenance mode[.]+? done!/)
    end
  end
end
