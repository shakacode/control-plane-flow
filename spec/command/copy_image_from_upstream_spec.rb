# frozen_string_literal: true

require "spec_helper"

describe Command::CopyImageFromUpstream do
  # rubocop:disable RSpec/AnyInstance
  before do
    allow(ENV).to receive(:fetch).with("CPLN_ENDPOINT", "https://api.cpln.io").and_return("https://api.cpln.io")
    allow(ENV).to receive(:fetch).with("CPLN_TOKEN", nil).and_return("token")
    allow(ENV).to receive(:fetch).with("CPLN_ORG", nil).and_return(nil)
    allow(ENV).to receive(:fetch).with("CPLN_ORG_UPSTREAM", nil).and_return(nil)
    allow(ENV).to receive(:fetch).with("CPLN_APP", nil).and_return(nil)
    allow(ENV).to receive(:fetch).with("CPLN_UPSTREAM", nil).and_return(nil)
    allow_any_instance_of(Config).to receive(:config_file_path).and_return("spec/fixtures/config.yml")
    allow_any_instance_of(described_class).to receive(:ensure_docker_running!)
    allow_any_instance_of(Controlplane).to receive(:profile_exists?).and_return(false)
    allow_any_instance_of(Controlplane).to receive(:profile_create).and_return(true)
    allow_any_instance_of(Controlplane).to receive(:profile_switch).and_return(true)
    allow_any_instance_of(Controlplane).to receive(:profile_delete).and_return(true)
    allow_any_instance_of(Controlplane).to receive(:image_login).and_return(true)
    allow_any_instance_of(Controlplane).to receive(:image_pull).and_return(true)
    allow_any_instance_of(Controlplane).to receive(:image_tag).and_return(true)
    allow_any_instance_of(Controlplane).to receive(:image_push).and_return(true)
  end

  it "copies commit from upstream if exists", vcr: true do
    allow_any_instance_of(Command::Base).to receive(:latest_image)
      .with("my-app-staging", "my-org-staging").and_return("my-app-staging:0_123abc")
    allow_any_instance_of(Command::Base).to receive(:latest_image)
      .with("my-app-production", "my-org-production").and_return("my-app-production:8_456def")

    expected_output = <<~OUTPUT
      Creating upstream profile... #{Shell.color('done!', :green)}
      Fetching upstream image URL... #{Shell.color('done!', :green)}
      Fetching app image URL... #{Shell.color('done!', :green)}
      Pulling image from 'my-org-staging.registry.cpln.io/my-app-staging:0_123abc'... #{Shell.color('done!', :green)}
      Pushing image to 'my-org-production.registry.cpln.io/my-app-production:9_123abc'... #{Shell.color('done!', :green)}
      Deleting upstream profile... #{Shell.color('done!', :green)}
    OUTPUT

    output = command_output do
      args = ["-a", "my-app-production", "--upstream-token", "upstream_token"]
      Cpl::Cli.start([described_class::NAME, *args])
    end

    expect(output).to eq(expected_output)
  end

  it "does not copy commit from upstream if not exists", vcr: true do
    allow_any_instance_of(Command::Base).to receive(:latest_image)
      .with("my-app-staging", "my-org-staging").and_return("my-app-staging:0")
    allow_any_instance_of(Command::Base).to receive(:latest_image)
      .with("my-app-production", "my-org-production").and_return("my-app-production:8_456def")

    expected_output = <<~OUTPUT
      Creating upstream profile... #{Shell.color('done!', :green)}
      Fetching upstream image URL... #{Shell.color('done!', :green)}
      Fetching app image URL... #{Shell.color('done!', :green)}
      Pulling image from 'my-org-staging.registry.cpln.io/my-app-staging:0'... #{Shell.color('done!', :green)}
      Pushing image to 'my-org-production.registry.cpln.io/my-app-production:9'... #{Shell.color('done!', :green)}
      Deleting upstream profile... #{Shell.color('done!', :green)}
    OUTPUT

    output = command_output do
      args = ["-a", "my-app-production", "--upstream-token", "upstream_token"]
      Cpl::Cli.start([described_class::NAME, *args])
    end

    expect(output).to eq(expected_output)
  end
  # rubocop:enable RSpec/AnyInstance
end
