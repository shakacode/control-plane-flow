# frozen_string_literal: true

require "spec_helper"

describe Command::CopyImageFromUpstream do
  describe "#call" do
    let(:config) do
      instance_double(
        Config,
        app: "test-app",
        org: "test-org",
        options: { upstream_token: "invalid-token", image: nil },
        find_app_config: { cpln_org: "upstream-org" }
      )
    end
    let(:cp) do
      instance_double(
        Controlplane,
        profile_exists?: false,
        profile_create: true,
        profile_switch: true,
        profile_delete: true
      )
    end
    let(:command) { described_class.new(config) }
    let(:progress) { StringIO.new }
    let(:forbidden_error) do
      response = instance_double(Net::HTTPForbidden, to_s: "403 Forbidden")
      ControlplaneApiDirect::ForbiddenError.new(
        url: "/org/upstream-org/gvc/upstream-app/image",
        response: response
      )
    end

    before do
      stub_env("CPLN_UPSTREAM", nil)
      stub_env("CPLN_ORG_UPSTREAM", nil)
      stub_env("CPLN_UPSTREAM_TOKEN", nil)
      allow(config).to receive(:[]).with(:upstream).and_return("upstream-app")
      allow(command).to receive_messages(
        cp: cp, progress: progress, ensure_docker_running!: true, random_four_digits: 1234
      )
      allow(cp).to receive(:latest_image).and_raise(forbidden_error)
    end

    it "reports a forbidden upstream fetch as a failed step and removes the temporary profile" do
      expect { command.call }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(ExitCode::ERROR_DEFAULT) }

      expect(progress.string).to include("Fetching upstream image URL... failed!")
      expect(progress.string).to include("Double check your org upstream-org. 403 Forbidden")
      expect(progress.string).to include("Deleting upstream profile... done!")
      expect(progress.string).not_to include("invalid-token")
      expect(cp).to have_received(:profile_switch).with("default")
      expect(cp).to have_received(:profile_delete).with("upstream-1234")
    end
  end
end
