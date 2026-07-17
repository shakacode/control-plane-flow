# frozen_string_literal: true

require "spec_helper"

describe ControlplaneApiDirect do
  let(:token_provider) { described_class::ApiToken.new }
  let(:slept_delays) { [] }
  let(:described_instance) do
    described_class.new(token_provider: token_provider, sleeper: ->(seconds) { slept_delays << seconds })
  end

  it "keeps no class-variable state" do
    expect(described_class.class_variables).to be_empty
  end

  it "uses the process-shared default token provider when none is injected" do
    allow(described_class.default_token_provider).to receive(:fetch)
      .and_return({ token: "shared-token", comes_from_profile: false })

    expect(described_class.new.api_token[:token]).to eq("shared-token")
  end

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
    def jwt_token(expires_in:)
      JWT.encode({ "exp" => Time.now.to_i + expires_in }, nil, "none")
    end

    it "returns token from CPLN_TOKEN" do
      stub_env("CPLN_TOKEN", "token_1")

      result = described_instance.api_token

      expect(result[:token]).to eq("token_1")
      expect(result[:comes_from_profile]).to be(false)
    end

    it "prefers CPLN_TOKEN over the profile token" do
      stub_env("CPLN_TOKEN", "token_1")
      allow(Shell).to receive(:cmd)

      described_instance.api_token

      expect(Shell).not_to have_received(:cmd)
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
      allow(Shell).to receive(:cmd).with("cpln", "profile", "token")
                                   .and_return({ output: "token_2\n", success: true })

      result = described_instance.api_token

      expect(result[:token]).to eq("token_2")
      expect(result[:comes_from_profile]).to be(true)
    end

    it "caches the profile token across fetches" do
      stub_env("CPLN_TOKEN", nil)
      allow(Shell).to receive(:cmd).with("cpln", "profile", "token")
                                   .and_return({ output: "token_2", success: true })

      2.times { described_instance.api_token }

      expect(Shell).to have_received(:cmd).once
    end

    it "raises error if token is not found" do
      stub_env("CPLN_TOKEN", nil)
      allow(Shell).to receive(:cmd).with("cpln", "profile", "token").and_return({ output: "", success: true })

      message = "Unknown API token format. " \
                "Please re-run 'cpln profile login' or set the correct CPLN_TOKEN env variable."
      expect do
        described_instance.api_token
      end.to raise_error(RuntimeError, message)
    end

    it "raises TokenRefreshError when 'cpln profile token' fails" do
      stub_env("CPLN_TOKEN", nil)
      allow(Shell).to receive(:cmd).with("cpln", "profile", "token")
                                   .and_return({ output: "garbage", success: false })

      expect do
        described_instance.api_token
      end.to raise_error(described_class::TokenRefreshError, /cpln profile login/)
    end

    it "refreshes a profile JWT that is about to expire" do
      stub_env("CPLN_TOKEN", nil)
      allow(Shell).to receive(:cmd).with("cpln", "profile", "token")
                                   .and_return({ output: jwt_token(expires_in: 60), success: true },
                                               { output: "refreshed-token", success: true })

      result = described_instance.api_token

      expect(result[:token]).to eq("refreshed-token")
      expect(result[:comes_from_profile]).to be(true)
      expect(Shell).to have_received(:cmd).twice
    end

    it "raises TokenRefreshError when refreshing an expiring token fails" do
      stub_env("CPLN_TOKEN", nil)
      allow(Shell).to receive(:cmd).with("cpln", "profile", "token")
                                   .and_return({ output: jwt_token(expires_in: 60), success: true },
                                               { output: "", success: false })

      expect do
        described_instance.api_token
      end.to raise_error(described_class::TokenRefreshError, /cpln profile token/)
    end

    it "does not refresh JWTs that are not close to expiring" do
      stub_env("CPLN_TOKEN", nil)
      token = jwt_token(expires_in: 3600)
      allow(Shell).to receive(:cmd).with("cpln", "profile", "token").and_return({ output: token, success: true })

      2.times { described_instance.api_token }

      expect(described_instance.api_token[:token]).to eq(token)
      expect(Shell).to have_received(:cmd).once
    end

    it "does not try to refresh non-JWT profile tokens" do
      stub_env("CPLN_TOKEN", nil)
      token = "service-account/key:abc.def/ghi+jkl=mnop"
      allow(Shell).to receive(:cmd).with("cpln", "profile", "token").and_return({ output: "#{token}\n", success: true })

      2.times { described_instance.api_token }

      expect(described_instance.api_token[:token]).to eq(token)
      expect(Shell).to have_received(:cmd).once
    end
  end

  describe ".reset_api_token" do
    it "resets the shared default token provider" do
      allow(described_class.default_token_provider).to receive(:reset)

      described_class.reset_api_token

      expect(described_class.default_token_provider).to have_received(:reset)
    end

    it "clears the cached token so the next fetch reloads it" do
      stub_env("CPLN_TOKEN", nil)
      allow(Shell).to receive(:cmd).with("cpln", "profile", "token")
                                   .and_return({ output: "token_1", success: true },
                                               { output: "token_2", success: true })

      expect(described_instance.api_token[:token]).to eq("token_1")
      token_provider.reset
      expect(described_instance.api_token[:token]).to eq("token_2")
    end
  end

  describe "#authorization_header" do
    it "uses bearer authentication for raw tokens" do
      stub_env("CPLN_TOKEN", "token_1")

      expect(described_instance.authorization_header).to eq("Bearer token_1")
    end

    it "does not double-prefix tokens that already include bearer authentication" do
      stub_env("CPLN_TOKEN", "Bearer token_1")

      expect(described_instance.authorization_header).to eq("Bearer token_1")
    end
  end

  describe "#call" do
    let(:http_connection) do
      instance_double(Net::HTTP, "use_ssl=": nil, "max_retries=": nil, "open_timeout=": nil,
                                 set_debug_output: nil, start: nil, finish: nil, started?: true)
    end

    before do
      stub_env("CPLN_TOKEN", "call-token")
      stub_env("CPLN_ENDPOINT", nil)
      allow(Net::HTTP).to receive(:new).and_return(http_connection)
    end

    def http_response(klass, code, body: nil, headers: {})
      response = klass.new("1.1", code.to_s, klass.name)
      response.instance_variable_set(:@read, true)
      response.instance_variable_set(:@body, body)
      headers.each { |key, value| response[key] = value }
      response
    end

    def ok_response(body: '{"result":"ok"}')
      http_response(Net::HTTPOK, 200, body: body)
    end

    it "parses the body of a 200 response" do
      allow(http_connection).to receive(:request).and_return(ok_response)

      result = described_instance.call("/org/my-org/gvc", method: :get)

      expect(result).to eq({ "result" => "ok" })
      expect(slept_delays).to be_empty
    end

    it "disables Net::HTTP's built-in retries and bounds the open timeout" do
      allow(http_connection).to receive(:request).and_return(ok_response)

      described_instance.call("/org/my-org/gvc", method: :get)

      expect(http_connection).to have_received(:max_retries=).with(0)
      expect(http_connection).to have_received(:open_timeout=).with(described_class::OPEN_TIMEOUT_SECONDS)
    end

    it "returns true for a 202 response" do
      allow(http_connection).to receive(:request).and_return(http_response(Net::HTTPAccepted, 202))

      expect(described_instance.call("/org/my-org/gvc", method: :delete)).to be(true)
    end

    it "returns nil for a 404 response without retrying" do
      allow(http_connection).to receive(:request).and_return(http_response(Net::HTTPNotFound, 404))

      expect(described_instance.call("/org/my-org/gvc/missing", method: :get)).to be_nil
      expect(http_connection).to have_received(:request).once
      expect(slept_delays).to be_empty
    end

    it "raises ForbiddenError for a 403 response without retrying" do
      allow(http_connection).to receive(:request).and_return(http_response(Net::HTTPForbidden, 403))

      expect do
        described_instance.call("/org/my-org/gvc", method: :get)
      end.to raise_error(described_class::ForbiddenError, /my-org/)
      expect(http_connection).to have_received(:request).once
      expect(slept_delays).to be_empty
    end

    it "fails immediately on a 400 response with no retries" do
      allow(http_connection).to receive(:request).and_return(http_response(Net::HTTPBadRequest, 400, body: "bad"))

      expect do
        described_instance.call("/org/my-org/gvc", method: :get)
      end.to raise_error(RuntimeError, /Net::HTTPBadRequest.*bad/m)
      expect(http_connection).to have_received(:request).once
      expect(slept_delays).to be_empty
    end

    it "fails immediately on a 401 response with no retries" do
      allow(http_connection).to receive(:request).and_return(http_response(Net::HTTPUnauthorized, 401))

      expect do
        described_instance.call("/org/my-org/gvc", method: :get)
      end.to raise_error(RuntimeError, /Net::HTTPUnauthorized/)
      expect(http_connection).to have_received(:request).once
      expect(slept_delays).to be_empty
    end

    it "retries a GET after a transient 500 and backs off with jitter" do
      allow(http_connection).to receive(:request)
        .and_return(http_response(Net::HTTPInternalServerError, 500, body: "boom"), ok_response)

      result = described_instance.call("/org/my-org/gvc", method: :get)

      expect(result).to eq({ "result" => "ok" })
      expect(http_connection).to have_received(:request).twice
      expect(slept_delays.size).to eq(1)
      expect(slept_delays.first).to be_between(0.25, 0.5)
    end

    it "retries a GET after a read timeout" do
      allow(http_connection).to receive(:request).and_invoke(
        ->(_request) { raise Net::ReadTimeout },
        ->(_request) { ok_response }
      )

      expect(described_instance.call("/org/my-org/gvc", method: :get)).to eq({ "result" => "ok" })
      expect(http_connection).to have_received(:request).twice
      expect(slept_delays.size).to eq(1)
    end

    it "retries a GET after a connect timeout" do
      allow(http_connection).to receive(:start).and_invoke(
        ->(*) { raise Net::OpenTimeout },
        ->(*) {}
      )
      allow(http_connection).to receive(:request).and_return(ok_response)

      expect(described_instance.call("/org/my-org/gvc", method: :get)).to eq({ "result" => "ok" })
      expect(slept_delays.size).to eq(1)
    end

    it "honors Retry-After on a 429 response" do
      allow(http_connection).to receive(:request)
        .and_return(http_response(Net::HTTPTooManyRequests, 429, headers: { "Retry-After" => "7" }), ok_response)

      expect(described_instance.call("/org/my-org/gvc", method: :get)).to eq({ "result" => "ok" })
      expect(slept_delays).to eq([7])
    end

    it "caps an excessive Retry-After value" do
      allow(http_connection).to receive(:request)
        .and_return(http_response(Net::HTTPTooManyRequests, 429, headers: { "Retry-After" => "9999" }), ok_response)

      expect(described_instance.call("/org/my-org/gvc", method: :get)).to eq({ "result" => "ok" })
      expect(slept_delays).to eq([described_class::Retrier::MAX_RETRY_DELAY_SECONDS])
    end

    it "falls back to backoff when Retry-After is not delta-seconds" do
      headers = { "Retry-After" => "Wed, 21 Oct 2026 07:28:00 GMT" }
      allow(http_connection).to receive(:request)
        .and_return(http_response(Net::HTTPTooManyRequests, 429, headers: headers), ok_response)

      expect(described_instance.call("/org/my-org/gvc", method: :get)).to eq({ "result" => "ok" })
      expect(slept_delays.size).to eq(1)
      expect(slept_delays.first).to be_between(0.25, 0.5)
    end

    it "gives up after the attempt cap and raises the original error" do
      allow(http_connection).to receive(:request)
        .and_return(http_response(Net::HTTPInternalServerError, 500, body: "boom"))

      expect do
        described_instance.call("/org/my-org/gvc", method: :get)
      end.to raise_error(RuntimeError, /Net::HTTPInternalServerError.*boom/m)
      expect(http_connection).to have_received(:request).exactly(3).times
      expect(slept_delays.size).to eq(2)
      expect(slept_delays.first).to be_between(0.25, 0.5)
      expect(slept_delays.last).to be_between(0.5, 1.0)
    end

    it "does not start a new attempt after the elapsed-time deadline" do
      allow(described_class::Retrier).to receive(:monotonic_time)
        .and_return(0, described_class::Retrier::MAX_TOTAL_RETRY_SECONDS + 1)
      allow(http_connection).to receive(:request)
        .and_return(http_response(Net::HTTPInternalServerError, 500, body: "boom"))

      expect do
        described_instance.call("/org/my-org/gvc", method: :get)
      end.to raise_error(RuntimeError, /Net::HTTPInternalServerError/)
      expect(http_connection).to have_received(:request).once
      expect(slept_delays).to be_empty
    end

    it "does not retry a POST on a 500 response" do
      allow(http_connection).to receive(:request)
        .and_return(http_response(Net::HTTPInternalServerError, 500, body: "boom"))

      expect do
        described_instance.call("/org/my-org/gvc", method: :post, body: { name: "gvc" })
      end.to raise_error(RuntimeError, /Net::HTTPInternalServerError/)
      expect(http_connection).to have_received(:request).once
      expect(slept_delays).to be_empty
    end

    it "does not retry a POST that fails after the request was sent" do
      allow(http_connection).to receive(:request).and_raise(Errno::ECONNRESET)

      expect do
        described_instance.call("/org/my-org/gvc", method: :post, body: { name: "gvc" })
      end.to raise_error(Errno::ECONNRESET)
      expect(http_connection).to have_received(:request).once
      expect(slept_delays).to be_empty
    end

    it "does not retry a PUT that fails after the request was sent" do
      allow(http_connection).to receive(:request).and_raise(Errno::ECONNRESET)

      expect do
        described_instance.call("/org/my-org/gvc", method: :put, body: { name: "gvc" })
      end.to raise_error(Errno::ECONNRESET)
      expect(http_connection).to have_received(:request).once
      expect(slept_delays).to be_empty
    end

    it "retries a POST when the connection fails before the request is sent" do
      allow(http_connection).to receive(:start).and_invoke(
        ->(*) { raise Errno::ECONNREFUSED },
        ->(*) {}
      )
      allow(http_connection).to receive(:request).and_return(ok_response)

      result = described_instance.call("/org/my-org/gvc", method: :post, body: { name: "gvc" })

      expect(result).to eq({ "result" => "ok" })
      expect(http_connection).to have_received(:request).once
      expect(slept_delays.size).to eq(1)
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
