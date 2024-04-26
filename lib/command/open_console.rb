# frozen_string_literal: true

module Command
  class OpenConsole < Base
    NAME = "open-console"
    OPTIONS = [
      app_option(required: true),
      workload_option
    ].freeze
    DESCRIPTION = "Opens the app console on Control Plane in the default browser"
    LONG_DESCRIPTION = <<~DESC
      - Opens the app console on Control Plane in the default browser
      - Can also go directly to a workload page if `--workload` is provided
    DESC

    def call
      workload = config.options[:workload]
      url = "https://console.cpln.io/console/org/#{config.org}/gvc/#{config.app}"
      url += "/workload/#{workload}" if workload
      url += "/-info"
      opener = Shell.cmd("which", "xdg-open", "open")[:output].split("\n").grep_v("not found").first

      Kernel.exec(opener, url)
    end
  end
end
