# frozen_string_literal: true

require "spec_helper"

describe Command::MaintenanceSetPage do
  before do
    allow(ENV).to receive(:fetch).with("CPLN_TOKEN", nil).and_return("token")
    allow_any_instance_of(Config).to receive(:find_app_config_file).and_return("spec/fixtures/config.yml") # rubocop:disable RSpec/AnyInstance
  end

  it "displays error if maintenance workload is not found", vcr: true do
    allow(Shell).to receive(:abort)
      .with("Can't find workload 'maintenance', " \
            "please create it with 'cpl apply-template maintenance -a my-app-staging'.")

    args = ["https://example.com/maintenance.html", "-a", "my-app-staging"]
    Cpl::Cli.start([described_class::NAME, *args])

    expect(Shell).to have_received(:abort).once
  end

  it "does nothing if maintenance workload does not use shakacode image", vcr: true do
    output = command_output do
      args = ["https://example.com/maintenance.html", "-a", "my-app-staging"]
      Cpl::Cli.start([described_class::NAME, *args])
    end

    expect(output).to be_empty
  end

  it "sets page for maintenance mode", vcr: true do
    expected_output = <<~OUTPUT
      Setting 'https://example.com/maintenance.html' as the page for maintenance mode... #{Shell.color('done!', :green)}
    OUTPUT

    output = command_output do
      args = ["https://example.com/maintenance.html", "-a", "my-app-staging"]
      Cpl::Cli.start([described_class::NAME, *args])
    end

    expect(output).to eq(expected_output)
  end
end
