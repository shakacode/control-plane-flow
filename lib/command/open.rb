# frozen_string_literal: true

module Command
  class Open < Base
    NAME = "open"
    OPTIONS = [
      app_option(required: true),
      workload_option
    ].freeze
    DESCRIPTION = "Opens the app endpoint URL in the default browser"
    LONG_DESCRIPTION = <<~HEREDOC
      - Opens the app endpoint URL in the default browser
    HEREDOC
    EXAMPLES = <<~HEREDOC
      ```sh
      # Opens the endpoint of the default workload (`one_off_workload`).
      cpl open -a $APP_NAME

      # Opens the endpoint of a specific workload.
      cpl open -a $APP_NAME -w $WORKLOAD_NAME
      ```
    HEREDOC

    def call
      workload = config.options[:workload] || config[:one_off_workload]
      data = cp.fetch_workload!(workload)
      url = data["status"]["endpoint"]
      opener = `which xdg-open open`.split("\n").grep_v("not found").first

      exec %(#{opener} "#{url}")
    end
  end
end
