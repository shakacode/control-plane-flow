# frozen_string_literal: true

require "spec_helper"

describe Command::PsRestart do
  context "when any workload does not exist" do
    let!(:app) { dummy_test_app("default", create_if_not_exists: true) }

    it "raises error" do
      result = run_cpflow_command("ps:restart", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find workload 'rails'")
    end
  end

  context "when all workloads exist" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    before do
      run_cpflow_command!("ps:start", "-a", app, "--wait")
    end

    it "restarts all workloads", :slow do
      result = run_cpflow_command("ps:restart", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Restarting workload 'rails'[.]+? done!/)
      expect(result[:stderr]).to match(/Restarting workload 'postgres'[.]+? done!/)
    end

    it "restarts specific workload", :slow do
      result = run_cpflow_command("ps:restart", "-a", app, "--workload", "rails")

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Restarting workload 'rails'[.]+? done!/)
      expect(result[:stderr]).not_to include("postgres")
    end
  end
end
