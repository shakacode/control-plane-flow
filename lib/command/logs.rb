# frozen_string_literal: true

module Command
  class Logs < Base
    NAME = "logs"
    OPTIONS = [
      app_option(required: true),
      workload_option
    ].freeze
    DESCRIPTION = "Light wrapper to display tailed raw logs for app/workload syntax"
    LONG_DESCRIPTION = <<~DESC
      - Light wrapper to display tailed raw logs for app/workload syntax
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Displays logs for the default workload (`one_off_workload`).
      cpl logs -a $APP_NAME

      # Displays logs for a specific workload.
      cpl logs -a $APP_NAME -w $WORKLOAD_NAME
      ```
    EX

    def call
      workload = config.options[:workload] || config[:one_off_workload]
      cp.logs(workload: workload)
    end
  end
end
