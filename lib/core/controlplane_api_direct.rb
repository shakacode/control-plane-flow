# frozen_string_literal: true

class ControlplaneApiDirect
  API_METHODS = {
    get: Net::HTTP::Get,
    patch: Net::HTTP::Patch,
    post: Net::HTTP::Post,
    put: Net::HTTP::Put,
    delete: Net::HTTP::Delete
  }.freeze
  API_HOSTS = { api: "https://api.cpln.io", logs: "https://logs.cpln.io" }.freeze

  # API_TOKEN_REGEX = Regexp.union(
  #  /^[\w.]{155}$/, # CPLN_TOKEN format
  #  /^[\w\-._]{1134}$/ # 'cpln profile token' format
  # ).freeze

  API_TOKEN_REGEX = /^[\w\-._]+$/.freeze
  API_TOKEN_EXPIRY_SECONDS = 300

  class << self
    attr_accessor :trace
  end

  def call(url, method:, host: :api, body: nil) # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity
    trace = ControlplaneApiDirect.trace
    uri = URI("#{api_host(host)}#{url}")
    request = API_METHODS[method].new(uri)
    request["Content-Type"] = "application/json"

    request["Authorization"] = api_token
    request.body = body.to_json if body

    Shell.debug(method.upcase, "#{uri} #{body&.to_json}")

    http = Net::HTTP.new(uri.hostname, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.set_debug_output($stdout) if trace

    response = http.start { |ht| ht.request(request) }

    case response
    when Net::HTTPOK
      JSON.parse(response.body)
    when Net::HTTPAccepted
      true
    when Net::HTTPNotFound
      nil
    when Net::HTTPForbidden
      org = self.class.parse_org(url)
      raise("Double check your org #{org}. #{response} #{response.body}")
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

  def api_token
    token = ENV.fetch("CPLN_TOKEN", nil) || `cpln profile token $CPLN_PROFILE`.chomp
    return token if token.match?(API_TOKEN_REGEX)

    raise "Unknown API token format. " \
          "Please re-run 'cpln profile login' or set the correct CPLN_TOKEN env variable."
  end

  def self.parse_org(url)
    url.match(%r{^/org/([^/]+)})[1]
  end
end
