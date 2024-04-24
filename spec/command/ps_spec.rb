# frozen_string_literal: true

require "spec_helper"

describe Command::Ps do
  context "when app does not exist" do
    let!(:app) { dummy_test_app }

    it "raises error" do
      result = run_cpl_command("ps", "-a", app)

      expect(result[:status]).to eq(1)
      expect(result[:stderr]).to include("Can't find app '#{app}'")
    end
  end

  context "when any workload does not exist" do
    let!(:app) { dummy_test_app("default", create_if_not_exists: true) }

    it "raises error" do
      result = run_cpl_command("ps", "-a", app)

      expect(result[:status]).to eq(1)
      expect(result[:stderr]).to include("Can't find workload 'rails'")
    end
  end

  context "when no replicas are running" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    before do
      run_cpl_command!("ps:start", "-a", app, "--wait")
      run_cpl_command!("ps:stop", "-a", app, "--wait")
    end

    it "displays nothing", :slow do
      result = run_cpl_command("ps", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to be_empty
    end
  end

  context "when replicas are running" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    before do
      run_cpl_command!("ps:start", "-a", app, "--wait")
    end

    it "displays currently running replicas for all workloads", :slow do
      result = run_cpl_command("ps", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("rails-")
      expect(result[:stdout]).to include("postgres-")
    end

    it "displays currently running replicas for specific workload", :slow do
      result = run_cpl_command("ps", "-a", app, "--workload", "rails")

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("rails-")
      expect(result[:stdout]).not_to include("postgres-")
    end
  end
end
