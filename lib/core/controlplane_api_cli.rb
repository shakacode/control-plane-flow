# frozen_string_literal: true

class ControlplaneApiCli
  def call(url, method:)
    result = Shell.cmd("cpln rest #{method} #{url} -o json", capture_stderr: true)
    raise(result[:output]) unless result[:success]

    JSON.parse(result[:output])
  end
end
