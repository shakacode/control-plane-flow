# frozen_string_literal: true

require "spec_helper"

describe Command::PsStop do
  let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

  before do
    run_cpflow_command!("ps:start", "-a", app, "--wait")
  end

  context "when no workload is provided" do
    it "stops all workloads", :slow do
      result = run_cpflow_command("ps:stop", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Stopping workload 'rails'[.]+? done!/)
      expect(result[:stderr]).to match(/Stopping workload 'postgres'[.]+? done!/)
    end

    it "stops all workloads and waits for them to not be ready", :slow do
      result = run_cpflow_command("ps:stop", "-a", app, "--wait")

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Stopping workload 'rails'[.]+? done!/)
      expect(result[:stderr]).to match(/Stopping workload 'postgres'[.]+? done!/)
      expect(result[:stderr]).to match(/Waiting for workload 'rails' to not be ready[.]+? done!/)
      expect(result[:stderr]).to match(/Waiting for workload 'postgres' to not be ready[.]+? done!/)
    end
  end

  context "when workload is provided" do
    it "stops specific workload", :slow do
      result = run_cpflow_command("ps:stop", "-a", app, "--workload", "rails")

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Stopping workload 'rails'[.]+? done!/)
      expect(result[:stderr]).not_to include("postgres")
    end
  end

  context "when replica is provided" do
    let!(:replica) do
      run_cpflow_command!("ps:stop", "-a", app, "--wait")
      run_cpflow_command!("ps:start", "-a", app, "--wait")

      result = run_cpflow_command!("ps", "-a", app, "--workload", "rails")
      result[:stdout].strip
    end

    it "stops specific replica", :slow do
      result = run_cpflow_command("ps:stop", "-a", app, "--workload", "rails", "--replica", replica)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Stopping replica '#{replica}'[.]+? done!/)
    end

    it "stops specific replica and waits for it to not be ready", :slow do
      result = run_cpflow_command("ps:stop", "-a", app, "--workload", "rails", "--replica", replica, "--wait")

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Stopping replica '#{replica}'[.]+? done!/)
      expect(result[:stderr]).to match(/Waiting for replica '#{replica}' to not be ready[.]+? done!/)
    end
  end
end
