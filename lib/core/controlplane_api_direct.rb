# frozen_string_literal: true

class ControlplaneApiDirect
  API_METHODS = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.freeze
  API_HOSTS = { api: "https://api.cpln.io", logs: "https://logs.cpln.io" }.freeze

  # API_TOKEN_REGEX = Regexp.union(
  #  /^[\w.]{155}$/, # CPLN_TOKEN format
  #  /^[\w\-._]{1134}$/ # 'cpln profile token' format
  # ).freeze

  API_TOKEN_REGEX = /^[\w\-._]+$/.freeze

  def call(url, method:, host: :api) # rubocop:disable Metrics/MethodLength
    uri = URI("#{API_HOSTS[host]}#{url}")
    request = API_METHODS[method].new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = api_token

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }

    case response
    when Net::HTTPOK
      JSON.parse(response.body)
    when Net::HTTPAccepted
      true
    when Net::HTTPNotFound
      nil
    else
      raise("#{response} #{response.body}")
    end
  end

  def api_token
    return @@api_token if defined?(@@api_token)

    @@api_token = ENV.fetch("CPLN_TOKEN", `cpln profile token`.chomp) # rubocop:disable Style/ClassVars
    return @@api_token if @@api_token.match?(API_TOKEN_REGEX)

    Shell.abort("Unknown API token format. " \
                "Please re-run 'cpln profile login' or set the correct CPLN_TOKEN env variable.")
  end
end
