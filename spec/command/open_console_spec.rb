# frozen_string_literal: true

require "spec_helper"

describe Command::OpenConsole do
  let!(:app) { dummy_test_app }

  context "when no workload is provided" do
    it "opens app console on Control Plane" do
      allow(Kernel).to receive(:exec)

      result = run_cpl_command("open-console", "-a", app)

      expected_url = %r{https://console.cpln.io/console/org/.+?/gvc/#{app}/-info}
      expect(Kernel).to have_received(:exec).with(anything, match(expected_url))
      expect(result[:status]).to eq(0)
    end
  end

  context "when workload is provided" do
    it "opens workload page on Control Plane" do
      allow(Kernel).to receive(:exec)

      result = run_cpl_command("open-console", "-a", app, "--workload", "rails")

      expected_url = %r{https://console.cpln.io/console/org/.+?/gvc/#{app}/workload/rails/-info}
      expect(Kernel).to have_received(:exec).with(anything, match(expected_url))
      expect(result[:status]).to eq(0)
    end
  end
end
