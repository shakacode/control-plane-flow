# frozen_string_literal: true

module Command
  class PsStop < Base
    NAME = "ps:stop"
    OPTIONS = [
      app_option(required: true),
      workload_option
    ].freeze
    DESCRIPTION = "Stops workloads in app"
    LONG_DESCRIPTION = <<~DESC
      - Stops workloads in app
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Stops all workloads in app.
      cpl ps:stop -a $APP_NAME

      # Stops a specific workload in app.
      cpl ps:stop -a $APP_NAME -w $WORKLOAD_NAME
      ```
    EX

    def call
      workloads = [config.options[:workload]] if config.options[:workload]
      workloads ||= config[:app_workloads] + config[:additional_workloads]

      workloads.each do |workload|
        step("Stopping workload '#{workload}'") do
          cp.workload_set_suspend(workload, true)
        end
      end
    end
  end
end
