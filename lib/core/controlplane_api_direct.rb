# frozen_string_literal: true

class ControlplaneApiDirect
  API_METHODS = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put }.freeze

  def call(url, method:) # rubocop:disable Metrics/MethodLength
    uri = URI("https://api.cpln.io#{url}")
    request = API_METHODS[method].new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = api_token

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }

    case response
    when Net::HTTPOK
      JSON.parse(response.body)
    when Net::HTTPNotFound
      nil
    else
      raise("#{response} #{response.body}")
    end
  end

  def api_token
    @@api_token ||= ENV.fetch("CPLN_TOKEN", `cpln profile token`.chomp) # rubocop:disable Style/ClassVars
  end
end
