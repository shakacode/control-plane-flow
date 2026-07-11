# frozen_string_literal: true

module Command
  class PsWait < Base
    NAME = "ps:wait"
    OPTIONS = [
      app_option(required: true),
      workload_option,
      location_option
    ].freeze
    DESCRIPTION = "Waits for workloads in app to be ready after re-deployment"
    LONG_DESCRIPTION = <<~DESC
      - Waits for workloads in app to be ready after re-deployment
      - Use Unix timeout command to set a maximum wait time (e.g., `timeout 300 cpflow ps:wait ...`)
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Waits for all workloads in app.
      cpflow ps:wait -a $APP_NAME

      # Waits for a specific workload in app.
      cpflow ps:wait -a $APP_NAME -w $WORKLOAD_NAME

      # Waits for all workloads with a 5-minute timeout.
      timeout 300 cpflow ps:wait -a $APP_NAME
      ```
    EX

    def call
      @workloads = [config.options[:workload]] if config.options[:workload]
      @workloads ||= config[:app_workloads] + config[:additional_workloads]

      wait_for_workloads_ready(@workloads, reverse: true)
    end
  end
end
