# frozen_string_literal: true

require "spec_helper"

describe ControlplaneApiDirect do
  let!(:described_instance) { described_class.new }

  describe "#api_host" do
    it "returns correct host for 'api' when CPLN_ENDPOINT is not set" do
      stub_env("CPLN_ENDPOINT", nil)

      host = described_instance.api_host(:api)

      expect(host).to eq("https://api.cpln.io")
    end

    it "returns correct host for 'api' when CPLN_ENDPOINT is set" do
      stub_env("CPLN_ENDPOINT", "http://api.cpln.io")

      host = described_instance.api_host(:api)

      expect(host).to eq("http://api.cpln.io")
    end

    it "returns correct host for 'logs'" do
      host = described_instance.api_host(:logs)

      expect(host).to eq("https://logs.cpln.io")
    end
  end

  describe "#api_token" do
    before do
      described_class.remove_class_variable(:@@api_token) if described_class.class_variable_defined?(:@@api_token)
    end

    after do
      described_class.remove_class_variable(:@@api_token) if described_class.class_variable_defined?(:@@api_token)
    end

    it "returns token from CPLN_TOKEN" do
      stub_env("CPLN_TOKEN", "token_1")

      result = described_instance.api_token

      expect(result[:token]).to eq("token_1")
      expect(result[:comes_from_profile]).to be(false)
    end

    it "accepts non-empty service account tokens with punctuation" do
      token = "service-account/key:abc.def/ghi+jkl=mnop"
      stub_env("CPLN_TOKEN", token)

      result = described_instance.api_token

      expect(result[:token]).to eq(token)
      expect(result[:comes_from_profile]).to be(false)
    end

    it "rejects tokens containing newlines" do
      stub_env("CPLN_TOKEN", "token\nsecond-line")

      message = "Unknown API token format. " \
                "Please re-run 'cpln profile login' or set the correct CPLN_TOKEN env variable."
      expect do
        described_instance.api_token
      end.to raise_error(RuntimeError, message)
    end

    it "rejects tokens containing carriage returns" do
      stub_env("CPLN_TOKEN", "token\rsecond-line")

      message = "Unknown API token format. " \
                "Please re-run 'cpln profile login' or set the correct CPLN_TOKEN env variable."
      expect do
        described_instance.api_token
      end.to raise_error(RuntimeError, message)
    end

    it "returns token from 'cpln profile token'" do
      stub_env("CPLN_TOKEN", nil)
      allow(Shell).to receive(:cmd).with("cpln", "profile", "token").and_return({ output: "token_2" })

      result = described_instance.api_token

      expect(result[:token]).to eq("token_2")
      expect(result[:comes_from_profile]).to be(true)
    end

    it "raises error if token is not found" do
      stub_env("CPLN_TOKEN", nil)
      allow(Shell).to receive(:cmd).with("cpln", "profile", "token").and_return({ output: "" })

      message = "Unknown API token format. " \
                "Please re-run 'cpln profile login' or set the correct CPLN_TOKEN env variable."
      expect do
        described_instance.api_token
      end.to raise_error(RuntimeError, message)
    end
  end

  describe "#authorization_header" do
    before do
      described_class.remove_class_variable(:@@api_token) if described_class.class_variable_defined?(:@@api_token)
    end

    after do
      described_class.remove_class_variable(:@@api_token) if described_class.class_variable_defined?(:@@api_token)
    end

    it "uses bearer authentication for raw tokens" do
      stub_env("CPLN_TOKEN", "token_1")

      expect(described_instance.authorization_header).to eq("Bearer token_1")
    end

    it "does not double-prefix tokens that already include bearer authentication" do
      stub_env("CPLN_TOKEN", "Bearer token_1")

      expect(described_instance.authorization_header).to eq("Bearer token_1")
    end
  end

  describe "#should_refresh_api_token?" do
    before do
      described_class.remove_class_variable(:@@api_token) if described_class.class_variable_defined?(:@@api_token)
    end

    after do
      described_class.remove_class_variable(:@@api_token) if described_class.class_variable_defined?(:@@api_token)
    end

    it "does not try to refresh non-JWT profile tokens" do
      stub_env("CPLN_TOKEN", nil)
      token = "service-account/key:abc.def/ghi+jkl=mnop"
      allow(Shell).to receive(:cmd).with("cpln", "profile", "token").and_return({ output: "#{token}\n" })

      expect(described_instance.should_refresh_api_token?).to be(false)
    end
  end

  describe ".parse_org" do
    it "returns correct org" do
      url = "/org/org1/gvc/gvc1"
      org = described_instance.class.parse_org(url)
      expect(org).to eq("org1")
    end

    it "returns nil when the URL does not include a concrete org" do
      expect(described_instance.class.parse_org("/org")).to be_nil
    end
  end

  describe "ForbiddenError" do
    it "omits the raw response body from org-scoped error messages" do
      response = instance_double(
        Net::HTTPForbidden,
        body: '{"internal":"id-123"}',
        to_s: "403 Forbidden"
      )
      error = ControlplaneApiDirect::ForbiddenError.new(url: "/org/my-org/gvc/my-app", response: response)

      expect(error.message).to eq("Double check your org my-org. 403 Forbidden")
      expect(error.message).not_to include("id-123")
    end
  end
end
