# frozen_string_literal: true

require "spec_helper"

describe ControlplaneApiDirect do
  let(:described_instance) { described_class.new }

  describe "#api_host" do
    it "returns correct host for 'api' when CPLN_ENDPOINT is not set" do
      allow(ENV).to receive(:fetch).with("CPLN_ENDPOINT", "https://api.cpln.io").and_return("https://api.cpln.io")

      host = described_instance.api_host(:api)

      expect(host).to eq("https://api.cpln.io")
    end

    it "returns correct host for 'api' when CPLN_ENDPOINT is set" do
      allow(ENV).to receive(:fetch).with("CPLN_ENDPOINT", "https://api.cpln.io").and_return("http://api.cpln.io")

      host = described_instance.api_host(:api)

      expect(host).to eq("http://api.cpln.io")
    end

    it "returns correct host for 'logs'" do
      host = described_instance.api_host(:logs)

      expect(host).to eq("https://logs.cpln.io")
    end
  end

  describe "#api_token" do
    it "returns token from CPLN_TOKEN" do
      allow(ENV).to receive(:fetch).with("CPLN_TOKEN", nil).and_return("token_1")

      token = described_instance.api_token

      expect(token).to eq("token_1")
    end

    it "returns token from 'cpln profile token'" do
      allow(ENV).to receive(:fetch).with("CPLN_TOKEN", nil).and_return(nil)
      allow(Shell).to receive(:cmd).with("cpln profile token $CPLN_PROFILE").and_return({ output: "token_2" })

      token = described_instance.api_token

      expect(token).to eq("token_2")
    end

    it "raises error if token is not found" do
      allow(ENV).to receive(:fetch).with("CPLN_TOKEN", nil).and_return(nil)
      allow(Shell).to receive(:cmd).with("cpln profile token $CPLN_PROFILE").and_return({ output: "" })

      message = "Unknown API token format. " \
                "Please re-run 'cpln profile login' or set the correct CPLN_TOKEN env variable."
      expect do
        described_instance.api_token
      end.to raise_error(RuntimeError, message)
    end
  end

  describe ".parse_org" do
    it "returns correct org" do
      url = "/org/org1/gvc/gvc1"
      org = described_instance.class.parse_org(url)
      expect(org).to eq("org1")
    end
  end
end
