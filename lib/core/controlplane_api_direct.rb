# frozen_string_literal: true

class ControlplaneApiDirect
  class RedactedDebugOutput
    SAFE_HEADERS = %w[Content-Type Content-Length Accept Host Date Cache-Control Connection].freeze
    HEADER_REGEX = /^([A-Za-z-]+): (.+)$/

    def <<(msg)
      $stdout << redact(msg)
    end

    private

    def redact(msg)
      msg.lines.map { |line| redact_line(line) }.join
    end

    def redact_line(line)
      match = line.match(HEADER_REGEX)
      return line.gsub(/[\w\-._]{50,}/, "[REDACTED]") unless match

      SAFE_HEADERS.any? { |h| h.casecmp(match[1]).zero? } ? line : "#{match[1]}: [REDACTED]\n"
    end
  end

  class ForbiddenError < StandardError
    attr_reader :url

    def initialize(url:, response:)
      @url = url
      org = ControlplaneApiDirect.parse_org(url)
      message =
        if org
          "Double check your org #{org}. #{response}"
        else
          "Control Plane API request to #{url} was forbidden. #{response}"
        end

      super(message)
    end
  end

  # Raised when fetching the API token via `cpln profile token` fails.
  class TokenRefreshError < StandardError; end

  API_METHODS = {
    get: Net::HTTP::Get,
    patch: Net::HTTP::Patch,
    post: Net::HTTP::Post,
    put: Net::HTTP::Put,
    delete: Net::HTTP::Delete
  }.freeze
  API_HOSTS = { api: "https://api.cpln.io", logs: "https://logs.cpln.io" }.freeze

  API_TOKEN_EXPIRY_SECONDS = 300

  # Only GET is retried after the request may have reached the server. The
  # remaining verbs mutate state, so they only retry connect-phase failures.
  IDEMPOTENT_METHODS = %i[get].freeze

  # Bounded so a retried connect failure fits within the retry deadline.
  OPEN_TIMEOUT_SECONDS = 10

  # Thread-safe API token cache. A single instance is shared process-wide by
  # default (see `default_token_provider`) so each `ControlplaneApiDirect.new`
  # per API call reuses the cached token; tests inject a fresh instance.
  class ApiToken
    def initialize
      @mutex = Mutex.new
      @data = nil
    end

    def fetch
      @mutex.synchronize do
        @data = load_token if @data.nil?
        refresh! if expiring_soon?
        @data
      end
    end

    def reset
      @mutex.synchronize { @data = nil }
    end

    private

    def load_token
      token = ENV.fetch("CPLN_TOKEN", nil)
      return validate!(token: token, comes_from_profile: false) if token

      validate!(token: fetch_profile_token, comes_from_profile: true)
    end

    def refresh!
      @data = validate!(token: fetch_profile_token, comes_from_profile: true)
    end

    def fetch_profile_token
      result = Shell.cmd("cpln", "profile", "token")
      unless result[:success]
        raise TokenRefreshError,
              "Failed to fetch the API token via 'cpln profile token'. " \
              "Please re-run 'cpln profile login' or set the CPLN_TOKEN env variable."
      end

      result[:output].chomp
    end

    def validate!(data)
      token = data[:token]
      # Allow any token that does not contain line breaks. Scoped service-account
      # tokens include punctuation such as '/', '+', ':', and '=', so format
      # validation is deferred to the Control Plane API.
      return data if token && !token.empty? && !token.match?(/[\r\n]/)

      raise "Unknown API token format. " \
            "Please re-run 'cpln profile login' or set the correct CPLN_TOKEN env variable."
    end

    # Returns `true` when a profile-sourced JWT expires within 5 minutes.
    def expiring_soon?
      return false unless @data[:comes_from_profile]

      payload, = JWT.decode(@data[:token], nil, false, algorithms: [])
      return false unless payload.is_a?(Hash) && payload["exp"]

      payload["exp"].to_i - Time.now.to_i <= API_TOKEN_EXPIRY_SECONDS
    rescue JWT::DecodeError
      false
    end
  end

  # Retry policy for transient failures: tracks attempts, enforces the attempt
  # and elapsed-time caps, and sleeps between tries (capped `Retry-After` when
  # the server provides one, exponential backoff with jitter otherwise).
  # The deadline is checked only before starting a new attempt: no new attempt
  # begins after `MAX_TOTAL_RETRY_SECONDS`, but an in-flight attempt may run
  # past it (bounded by the per-attempt open/read timeouts).
  class Retrier
    MAX_ATTEMPTS = 3
    MAX_TOTAL_RETRY_SECONDS = 120
    BASE_RETRY_DELAY_SECONDS = 0.5
    MAX_RETRY_DELAY_SECONDS = 10
    TRANSIENT_NETWORK_ERRORS = [
      Net::OpenTimeout, Net::ReadTimeout,
      Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EPIPE, Errno::ETIMEDOUT,
      EOFError, OpenSSL::SSL::SSLError, SocketError
    ].freeze

    def initialize(sleeper:)
      @sleeper = sleeper
      @attempts_made = 1
      @deadline = Retrier.monotonic_time + MAX_TOTAL_RETRY_SECONDS
    end

    def self.monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Whether to retry a 429/5xx response received for an idempotent request.
    def retry_response?(response, idempotent)
      retriable = response.is_a?(Net::HTTPServerError) || response.is_a?(Net::HTTPTooManyRequests)
      return false unless idempotent && retriable

      retry?(retry_after: response["Retry-After"])
    end

    # Whether to retry a transient network error. Non-idempotent requests only
    # retry when the failure happened before the request may have hit the wire.
    def retry_exception?(idempotent, request_sent)
      return false if request_sent && !idempotent

      retry?
    end

    private

    # When another attempt is allowed, sleeps through the delay and returns `true`.
    def retry?(retry_after: nil)
      return false if @attempts_made >= MAX_ATTEMPTS || Retrier.monotonic_time >= @deadline

      @sleeper.call(next_delay(retry_after))
      @attempts_made += 1
      true
    end

    def next_delay(retry_after)
      seconds = parse_retry_after(retry_after)
      return seconds if seconds

      backoff = [BASE_RETRY_DELAY_SECONDS * (2**(@attempts_made - 1)), MAX_RETRY_DELAY_SECONDS].min
      (backoff / 2) + (rand * backoff / 2)
    end

    # Supports the delta-seconds form of `Retry-After`, capped so a slow or
    # misconfigured server cannot stall the CLI.
    def parse_retry_after(value)
      return nil unless value.to_s.match?(/\A\d+\z/)

      [Integer(value, 10), MAX_RETRY_DELAY_SECONDS].min
    end
  end

  class << self
    attr_accessor :trace
    attr_reader :default_token_provider

    # Preserved seam: `Controlplane#profile_switch` invalidates the cached
    # token when the CPLN profile changes.
    def reset_api_token = default_token_provider.reset
  end

  @default_token_provider = ApiToken.new

  def initialize(token_provider: ControlplaneApiDirect.default_token_provider, sleeper: nil)
    @token_provider = token_provider
    @sleeper = sleeper || ->(seconds) { Kernel.sleep(seconds) }
  end

  def call(url, method:, host: :api, body: nil)
    uri = URI("#{api_host(host)}#{url}")
    # Token fetch and request construction happen outside the transient rescue
    # in attempt_request so their failures (e.g. TokenRefreshError from the
    # `cpln` shell-out) are never misclassified as retryable network errors.
    request = build_request(uri, method, body)
    retrier = Retrier.new(sleeper: @sleeper)

    Shell.debug(method.upcase, "#{uri} #{body&.to_json}")

    loop do
      response = attempt_request(uri, request, method, retrier)
      return handle_response(response, url) if response
    end
  end

  def api_host(host)
    case host
    when :api
      ENV.fetch("CPLN_ENDPOINT", API_HOSTS[host])
    else
      API_HOSTS[host]
    end
  end

  def authorization_header
    token = api_token[:token]
    return token if token.match?(/\ABearer\s+/i)

    "Bearer #{token}"
  end

  def api_token = @token_provider.fetch

  def self.parse_org(url)
    url.match(%r{^/org/([^/]+)})&.[](1)
  end

  private

  # Returns the response, or `nil` when the attempt failed transiently and the
  # retrier approved (and already slept before) another attempt. Only the
  # transport phase (connect + request) is covered by the transient rescue.
  def attempt_request(uri, request, method, retrier)
    request_sent = false
    idempotent = IDEMPOTENT_METHODS.include?(method)
    response = transport_request(uri, request) { request_sent = true }
    return response unless retrier.retry_response?(response, idempotent)

    nil
  rescue *Retrier::TRANSIENT_NETWORK_ERRORS
    raise unless retrier.retry_exception?(idempotent, request_sent)

    nil
  end

  def transport_request(uri, request)
    http = build_http(uri)
    http.start
    yield
    begin
      http.request(request)
    ensure
      http.finish if http.started?
    end
  end

  def build_request(uri, method, body)
    request = API_METHODS[method].new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = authorization_header
    request.body = body.to_json if body
    request
  end

  def build_http(uri)
    http = Net::HTTP.new(uri.hostname, uri.port)
    http.use_ssl = uri.scheme == "https"
    # Net::HTTP transparently re-sends requests it deems idempotent once on
    # mid-flight failures; disable so the Retrier owns the entire retry policy.
    http.max_retries = 0
    http.open_timeout = OPEN_TIMEOUT_SECONDS
    http.set_debug_output(RedactedDebugOutput.new) if ControlplaneApiDirect.trace
    http
  end

  def handle_response(response, url)
    case response
    when Net::HTTPOK then JSON.parse(response.body)
    when Net::HTTPAccepted then true
    when Net::HTTPNotFound then nil
    when Net::HTTPForbidden then raise(ForbiddenError.new(url: url, response: response))
    else raise("#{response} #{response.body}")
    end
  end
end
