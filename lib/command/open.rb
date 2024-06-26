# frozen_string_literal: true

module Command
  class Open < Base
    NAME = "open"
    OPTIONS = [
      app_option(required: true),
      workload_option
    ].freeze
    DESCRIPTION = "Opens the app endpoint URL in the default browser"
    LONG_DESCRIPTION = <<~DESC
      - Opens the app endpoint URL in the default browser
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Opens the endpoint of the default workload (`one_off_workload`).
      cpflow open -a $APP_NAME

      # Opens the endpoint of a specific workload.
      cpflow open -a $APP_NAME -w $WORKLOAD_NAME
      ```
    EX

    def call
      workload = config.options[:workload] || config[:one_off_workload]
      data = cp.fetch_workload!(workload)
      url = data["status"]["endpoint"]
      opener = Shell.cmd("which", "xdg-open", "open")[:output].split("\n").grep_v("not found").first

      Kernel.exec(opener, url)
    end
  end
end
