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
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Waits for all workloads in app.
      cpl ps:wait -a $APP_NAME

      # Waits for a specific workload in app.
      cpl ps:swait -a $APP_NAME -w $WORKLOAD_NAME
      ```
    EX

    def call # rubocop:disable Metrics/MethodLength
      @workloads = [config.options[:workload]] if config.options[:workload]
      @workloads ||= config[:app_workloads] + config[:additional_workloads]

      @workloads.reverse_each do |workload|
        if cp.workload_suspended?(workload)
          progress.puts("Workload '#{workload}' is suspended. Skipping...")
        else
          step("Waiting for workload '#{workload}' to be ready", retry_on_failure: true) do
            cp.workload_deployments_ready?(workload, location: config.location, expected_status: true)
          end
        end
      end
    end
  end
end
