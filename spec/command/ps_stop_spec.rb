# frozen_string_literal: true

require "spec_helper"

describe Command::PsStop do
  let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

  before do
    run_cpl_command!("ps:start", "-a", app, "--wait")
  end

  it "stops all workloads", :slow do
    result = run_cpl_command("ps:stop", "-a", app)

    expect(result[:status]).to eq(0)
    expect(result[:stderr]).to match(/Stopping workload 'rails'[.]+? done!/)
    expect(result[:stderr]).to match(/Stopping workload 'redis'[.]+? done!/)
    expect(result[:stderr]).to match(/Stopping workload 'postgres'[.]+? done!/)
  end

  it "stops specific workload", :slow do
    result = run_cpl_command("ps:stop", "-a", app, "--workload", "rails")

    expect(result[:status]).to eq(0)
    expect(result[:stderr]).to match(/Stopping workload 'rails'[.]+? done!/)
    expect(result[:stderr]).not_to include("redis")
    expect(result[:stderr]).not_to include("postgres")
  end

  it "stops all workloads and waits for them to not be ready", :slow do
    result = run_cpl_command("ps:stop", "-a", app, "--wait")

    expect(result[:status]).to eq(0)
    expect(result[:stderr]).to match(/Stopping workload 'rails'[.]+? done!/)
    expect(result[:stderr]).to match(/Stopping workload 'redis'[.]+? done!/)
    expect(result[:stderr]).to match(/Stopping workload 'postgres'[.]+? done!/)
    expect(result[:stderr]).to match(/Waiting for workload 'rails' to not be ready[.]+? done!/)
    expect(result[:stderr]).to match(/Waiting for workload 'redis' to not be ready[.]+? done!/)
    expect(result[:stderr]).to match(/Waiting for workload 'postgres' to not be ready[.]+? done!/)
  end
end
