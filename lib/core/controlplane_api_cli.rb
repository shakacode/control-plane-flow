# frozen_string_literal: true

class ControlplaneApiCli
  def call(url, method:)
    response = `cpln rest #{method} #{url} -o json`
    raise(response) unless $CHILD_STATUS.success?

    JSON.parse(response)
  end
end
