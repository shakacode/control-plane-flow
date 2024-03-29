# frozen_string_literal: true

require "spec_helper"

describe Command::MaintenanceOn do
  # rubocop:disable RSpec/AnyInstance
  before do
    allow(ENV).to receive(:fetch).with("CPLN_ENDPOINT", "https://api.cpln.io").and_return("https://api.cpln.io")
    allow(ENV).to receive(:fetch).with("CPLN_TOKEN", nil).and_return("token")
    allow(ENV).to receive(:fetch).with("CPLN_ORG", nil).and_return(nil)
    allow(ENV).to receive(:fetch).with("CPLN_APP", nil).and_return(nil)
    allow_any_instance_of(Config).to receive(:config_file_path).and_return("spec/fixtures/config.yml")
    allow(Kernel).to receive(:sleep).and_return(true)
  end
  # rubocop:enable RSpec/AnyInstance

  it "displays error if domain is not found", vcr: true do
    allow(Shell).to receive(:abort)
      .with("Can't find domain. " \
            "Maintenance mode is only supported for domains that use path based routing mode " \
            "and have a route configured for the prefix '/' on either port 80 or 443.")

    args = ["-a", "my-app-staging"]
    run_command(described_class::NAME, *args)

    expect(Shell).to have_received(:abort).once
  end

  it "displays error if maintenance workload is not found", vcr: true do
    allow(Shell).to receive(:abort)
      .with("Can't find workload 'maintenance', " \
            "please create it with 'cpl apply-template maintenance -a my-app-staging'.")

    args = ["-a", "my-app-staging"]
    run_command(described_class::NAME, *args)

    expect(Shell).to have_received(:abort).once
  end

  it "does nothing if maintenance mode is already enabled", vcr: true do
    expected_output = <<~OUTPUT
      Maintenance mode is already enabled for app 'my-app-staging'.
    OUTPUT

    args = ["-a", "my-app-staging"]
    result = run_command(described_class::NAME, *args)

    expect(result[:stderr]).to eq(expected_output)
  end

  it "enables maintenance mode", vcr: true do
    expected_output = <<~OUTPUT
      Starting workload 'maintenance'... done!

      Waiting for workload 'maintenance' to be ready... done!

      Switching workload for domain 'my-app-staging.example.com' to 'maintenance'... done!

      Stopping workload 'rails'... done!
      Stopping workload 'redis'... done!
      Stopping workload 'postgres'... done!

      Waiting for workload 'rails' to not be ready... done!
      Waiting for workload 'redis' to not be ready... done!
      Waiting for workload 'postgres' to not be ready... done!

      Maintenance mode enabled for app 'my-app-staging'.
    OUTPUT

    args = ["-a", "my-app-staging"]
    result = run_command(described_class::NAME, *args)

    expect(result[:stderr]).to eq(expected_output)
  end
end
