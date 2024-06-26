# frozen_string_literal: true

require "spec_helper"

describe Command::Open do
  context "when one-off workload does not exist" do
    let!(:app) { dummy_test_app("default", create_if_not_exists: true) }

    it "raises error" do
      result = run_cpflow_command("open", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find workload 'rails'")
    end
  end

  context "when no workload is provided" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    it "opens endpoint of one-off workload" do
      allow(Kernel).to receive(:exec)

      result = run_cpflow_command("open", "-a", app)

      expected_url = %r{https://rails-.+?.cpln.app}
      expect(Kernel).to have_received(:exec).with(anything, match(expected_url))
      expect(result[:status]).to eq(0)
    end
  end

  context "when workload is provided" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    it "opens endpoint of specific workload" do
      allow(Kernel).to receive(:exec)

      result = run_cpflow_command("open", "-a", app, "--workload", "postgres")

      expected_url = %r{https://postgres-.+?.cpln.app}
      expect(Kernel).to have_received(:exec).with(anything, match(expected_url))
      expect(result[:status]).to eq(0)
    end
  end
end
