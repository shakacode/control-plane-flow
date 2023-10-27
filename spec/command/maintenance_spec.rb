# frozen_string_literal: true

require "spec_helper"

describe Command::Maintenance do
  before do
    allow(ENV).to receive(:fetch).with("CPLN_ENDPOINT", "https://api.cpln.io").and_return("https://api.cpln.io")
    allow(ENV).to receive(:fetch).with("CPLN_TOKEN", nil).and_return("token")
    allow(ENV).to receive(:fetch).with("CPLN_ORG", nil).and_return(nil)
    allow_any_instance_of(Config).to receive(:find_app_config_file).and_return("spec/fixtures/config.yml") # rubocop:disable RSpec/AnyInstance
  end

  it "displays error if domain is not found", vcr: true do
    allow(Shell).to receive(:abort)
      .with("Can't find domain. " \
            "Maintenance mode is only supported for domains that use path based routing mode " \
            "and have a route configured for the prefix '/' on either port 80 or 443.")

    args = ["-a", "my-app-staging"]
    Cpl::Cli.start([described_class::NAME, *args])

    expect(Shell).to have_received(:abort).once
  end

  it "displays 'on' if maintenance mode is enabled", vcr: true do
    allow($stdout).to receive(:puts).with("on")

    args = ["-a", "my-app-staging"]
    Cpl::Cli.start([described_class::NAME, *args])

    expect($stdout).to have_received(:puts).once
  end

  it "displays 'off' if maintenance mode is disabled", vcr: true do
    allow($stdout).to receive(:puts).with("off")

    args = ["-a", "my-app-staging"]
    Cpl::Cli.start([described_class::NAME, *args])

    expect($stdout).to have_received(:puts).once
  end
end
