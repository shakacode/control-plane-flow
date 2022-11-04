# frozen_string_literal: true

class ControlplaneApiCli
  def call(url, method:)
    response = `cpln rest #{method} #{url} -o json`
    raise(response) unless $?.success? # rubocop:disable Style/SpecialGlobalVars

    JSON.parse(response)
  end
end
