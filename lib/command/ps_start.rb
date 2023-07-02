# frozen_string_literal: true

module Command
  class PsStart < Base
    NAME = "ps:start"
    OPTIONS = [
      app_option(required: true),
      workload_option,
      wait_option("workload to be ready")
    ].freeze
    DESCRIPTION = "Starts workloads in app"
    LONG_DESCRIPTION = <<~DESC
      - Starts workloads in app
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Starts all workloads in app.
      cpl ps:start -a $APP_NAME

      # Starts a specific workload in app.
      cpl ps:start -a $APP_NAME -w $WORKLOAD_NAME
      ```
    EX

    def call
      @workloads = [config.options[:workload]] if config.options[:workload]
      @workloads ||= config[:app_workloads] + config[:additional_workloads]

      @workloads.reverse_each do |workload|
        step("Starting workload '#{workload}'") do
          cp.set_workload_suspend(workload, false)
        end
      end

      wait_for_ready if config.options[:wait]
    end

    private

    def wait_for_ready
      progress.puts

      @workloads.reverse_each do |workload|
        step("Waiting for workload '#{workload}' to be ready", retry_on_failure: true) do
          cp.workload_deployments_ready?(workload, expected_status: true)
        end
      end
    end
  end
end
