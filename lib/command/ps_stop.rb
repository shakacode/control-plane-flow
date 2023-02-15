# frozen_string_literal: true

module Command
  class PsStop < Base
    NAME = "ps:stop"
    OPTIONS = [
      app_option(required: true),
      workload_option,
      wait_option("workload to be not ready")
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
      @workloads = [config.options[:workload]] if config.options[:workload]
      @workloads ||= config[:app_workloads] + config[:additional_workloads]

      @workloads.each do |workload|
        step("Stopping workload '#{workload}'") do
          cp.workload_set_suspend(workload, true)
        end
      end

      wait_for_not_ready if config.options[:wait]
    end

    private

    def wait_for_not_ready
      progress.puts

      @workloads.each do |workload|
        step("Waiting for workload '#{workload}' to be not ready", retry_on_failure: true) do
          cp.fetch_workload_deployments(workload)&.dig("items")&.all? do |item|
            !item.dig("status", "ready")
          end
        end
      end
    end
  end
end
