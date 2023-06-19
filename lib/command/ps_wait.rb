# frozen_string_literal: true

module Command
  class PsWait < Base
    NAME = "ps:wait"
    OPTIONS = [
      app_option(required: true),
      workload_option
    ].freeze
    DESCRIPTION = "Waits for workloads in app to be ready after re-deployment"
    LONG_DESCRIPTION = <<~DESC
      - Waits for workloads in app to be ready after re-deployment
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Waits for all workloads in app.
      cpl ps:wait -a $APP_NAME

      # Waits for a specific workload in app.
      cpl ps:swait -a $APP_NAME -w $WORKLOAD_NAME
      ```
    EX

    def call
      @workloads = [config.options[:workload]] if config.options[:workload]
      @workloads ||= config[:app_workloads] + config[:additional_workloads]

      @workloads.reverse_each do |workload|
        step("Waiting for workload '#{workload}' to be ready", retry_on_failure: true) do
          cp.wait_for_workload_deployments(workload, ready: true)
        end
      end
    end
  end
end
