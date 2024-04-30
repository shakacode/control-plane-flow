# frozen_string_literal: true

module Command
  class Logs < Base
    NAME = "logs"
    OPTIONS = [
      app_option(required: true),
      workload_option,
      logs_limit_option,
      logs_since_option
    ].freeze
    DESCRIPTION = "Light wrapper to display tailed raw logs for app/workload syntax"
    LONG_DESCRIPTION = <<~DESC
      - Light wrapper to display tailed raw logs for app/workload syntax
      - Defaults to showing the last 200 entries from the past 1 hour before tailing
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Displays logs for the default workload (`one_off_workload`).
      cpl logs -a $APP_NAME

      # Displays logs for a specific workload.
      cpl logs -a $APP_NAME -w $WORKLOAD_NAME

      # Uses a different limit on number of entries.
      cpl logs -a $APP_NAME --limit 100

      # Uses a different loopback window.
      cpl logs -a $APP_NAME --since 30min
      ```
    EX

    def call
      workload = config.options[:workload] || config[:one_off_workload]
      limit = config.options[:limit]
      since = config.options[:since]

      cp.logs(workload: workload, limit: limit, since: since)
    end
  end
end
