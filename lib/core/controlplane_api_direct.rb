# frozen_string_literal: true

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

class ControlplaneApiDirect
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

  API_METHODS = {
    get: Net::HTTP::Get,
    patch: Net::HTTP::Patch,
    post: Net::HTTP::Post,
    put: Net::HTTP::Put,
    delete: Net::HTTP::Delete
  }.freeze
  API_HOSTS = { api: "https://api.cpln.io", logs: "https://logs.cpln.io" }.freeze

  API_TOKEN_EXPIRY_SECONDS = 300

  class << self
    attr_accessor :trace
  end

  def call(url, method:, host: :api, body: nil) # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity
    trace = ControlplaneApiDirect.trace
    uri = URI("#{api_host(host)}#{url}")
    request = API_METHODS[method].new(uri)
    request["Content-Type"] = "application/json"

    refresh_api_token if should_refresh_api_token?

    request["Authorization"] = authorization_header
    request.body = body.to_json if body

    Shell.debug(method.upcase, "#{uri} #{body&.to_json}")

    http = Net::HTTP.new(uri.hostname, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.set_debug_output(RedactedDebugOutput.new) if trace

    response = http.start { |ht| ht.request(request) }

    case response
    when Net::HTTPOK
      JSON.parse(response.body)
    when Net::HTTPAccepted
      true
    when Net::HTTPNotFound
      nil
    when Net::HTTPForbidden
      raise ForbiddenError.new(url: url, response: response)
    else
      raise("#{response} #{response.body}")
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

  # rubocop:disable Style/ClassVars
  def api_token # rubocop:disable Metrics/MethodLength
    return @@api_token if defined?(@@api_token)

    @@api_token = {
      token: ENV.fetch("CPLN_TOKEN", nil),
      comes_from_profile: false
    }
    if @@api_token[:token].nil?
      @@api_token = {
        token: Shell.cmd("cpln", "profile", "token")[:output].chomp,
        comes_from_profile: true
      }
    end
    token = @@api_token[:token]
    # Allow any token that does not contain line breaks. Scoped service-account
    # tokens include punctuation such as '/', '+', ':', and '=', so format
    # validation is deferred to the Control Plane API.
    return @@api_token if token && !token.empty? && !token.match?(/[\r\n]/)

    raise "Unknown API token format. " \
          "Please re-run 'cpln profile login' or set the correct CPLN_TOKEN env variable."
  end

  # Returns `true` when the token is about to expire in 5 minutes
  def should_refresh_api_token?
    return false unless api_token[:comes_from_profile]

    payload, = JWT.decode(api_token[:token], nil, false, algorithms: [])
    return false unless payload.is_a?(Hash) && payload["exp"]

    difference_in_seconds = payload["exp"].to_i - Time.now.to_i

    difference_in_seconds <= API_TOKEN_EXPIRY_SECONDS
  rescue JWT::DecodeError
    false
  end

  def refresh_api_token
    @@api_token[:token] = Shell.cmd("cpln", "profile", "token")[:output].chomp
  end

  def self.reset_api_token
    remove_class_variable(:@@api_token) if defined?(@@api_token)
  end
  # rubocop:enable Style/ClassVars

  def self.parse_org(url)
    url.match(%r{^/org/([^/]+)})&.[](1)
  end
end
