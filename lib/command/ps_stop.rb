# frozen_string_literal: true

module Command
  class PsStop < Base
    NAME = "ps:stop"
    OPTIONS = [
      app_option(required: true),
      workload_option,
      replica_option,
      location_option,
      wait_option("workload to not be ready")
    ].freeze
    DESCRIPTION = "Stops workloads in app"
    LONG_DESCRIPTION = <<~DESC
      - Stops workloads in app
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Stops all workloads in app.
      cpflow ps:stop -a $APP_NAME

      # Stops a specific workload in app.
      cpflow ps:stop -a $APP_NAME -w $WORKLOAD_NAME

      # Stops a specific replica of a workload.
      cpflow ps:stop -a $APP_NAME -w $WORKLOAD_NAME -r $REPLICA_NAME
      ```
    EX

    def call
      workload = config.options[:workload]
      replica = config.options[:replica]
      if replica
        stop_replica(workload, replica)
      else
        workloads = [workload] if workload
        workloads ||= config[:app_workloads] + config[:additional_workloads]

        stop_workloads(workloads)
      end
    end

    private

    def stop_workloads(workloads)
      workloads.each do |workload|
        step("Stopping workload '#{workload}'") do
          cp.set_workload_suspend(workload, true)
        end
      end

      wait_for_workloads_not_ready(workloads) if config.options[:wait]
    end

    def stop_replica(workload, replica)
      step("Stopping replica '#{replica}'", retry_on_failure: true) do
        cp.stop_workload_replica(workload, replica, location: config.location)
      end

      wait_for_replica_not_ready(workload, replica) if config.options[:wait]
    end

    def wait_for_workloads_not_ready(workloads)
      progress.puts

      workloads.each do |workload|
        step("Waiting for workload '#{workload}' to not be ready", retry_on_failure: true) do
          cp.workload_deployments_ready?(workload, location: config.location, expected_status: false)
        end
      end
    end

    def wait_for_replica_not_ready(workload, replica)
      progress.puts

      step("Waiting for replica '#{replica}' to not be ready", retry_on_failure: true) do
        result = cp.fetch_workload_replicas(workload, location: config.location)
        items = result&.dig("items")
        items && !items.include?(replica)
      end
    end
  end
end
