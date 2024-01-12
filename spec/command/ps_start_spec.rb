# frozen_string_literal: true

require "spec_helper"

describe Command::PsStart do
  let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

  before do
    run_cpl_command!("ps:stop", "-a", app, "--wait")
  end

  it "starts all workloads", :slow do
    result = run_cpl_command("ps:start", "-a", app)

    expect(result[:status]).to eq(0)
    expect(result[:stderr]).to match(/Starting workload 'rails'[.]+? done!/)
    expect(result[:stderr]).to match(/Starting workload 'redis'[.]+? done!/)
    expect(result[:stderr]).to match(/Starting workload 'postgres'[.]+? done!/)
  end

  it "starts specific workload", :slow do
    result = run_cpl_command("ps:start", "-a", app, "--workload", "rails")

    expect(result[:status]).to eq(0)
    expect(result[:stderr]).to match(/Starting workload 'rails'[.]+? done!/)
    expect(result[:stderr]).not_to include("redis")
    expect(result[:stderr]).not_to include("postgres")
  end

  it "starts all workloads and waits for them to be ready", :slow do
    result = run_cpl_command("ps:start", "-a", app, "--wait")

    expect(result[:status]).to eq(0)
    expect(result[:stderr]).to match(/Starting workload 'rails'[.]+? done!/)
    expect(result[:stderr]).to match(/Starting workload 'redis'[.]+? done!/)
    expect(result[:stderr]).to match(/Starting workload 'postgres'[.]+? done!/)
    expect(result[:stderr]).to match(/Waiting for workload 'rails' to be ready[.]+? done!/)
    expect(result[:stderr]).to match(/Waiting for workload 'redis' to be ready[.]+? done!/)
    expect(result[:stderr]).to match(/Waiting for workload 'postgres' to be ready[.]+? done!/)
  end
end
