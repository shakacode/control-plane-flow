# frozen_string_literal: true

require "spec_helper"

describe Command::PsWait do
  let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

  before do
    run_cpl_command!("ps:start", "-a", app, "--wait")
    run_cpl_command!("ps:restart", "-a", app)
  end

  it "waits for all workloads to be ready", :slow do
    result = run_cpl_command("ps:wait", "-a", app)

    expect(result[:status]).to eq(0)
    expect(result[:stderr]).to match(/Waiting for workload 'rails' to be ready[.]+? done!/)
    expect(result[:stderr]).to match(/Waiting for workload 'postgres' to be ready[.]+? done!/)
  end

  it "waits for specific workload to be ready", :slow do
    result = run_cpl_command("ps:wait", "-a", app, "--workload", "rails")

    expect(result[:status]).to eq(0)
    expect(result[:stderr]).to match(/Waiting for workload 'rails' to be ready[.]+? done!/)
    expect(result[:stderr]).not_to include("postgres")
  end
end
