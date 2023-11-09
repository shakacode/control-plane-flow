# frozen_string_literal: true

module Command
  class Ps < Base
    NAME = "ps"
    OPTIONS = [
      app_option(required: true),
      workload_option
    ].freeze
    DESCRIPTION = "Shows running replicas in app"
    LONG_DESCRIPTION = <<~DESC
      - Shows running replicas in app
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Shows running replicas in app, for all workloads.
      cpl ps -a $APP_NAME

      # Shows running replicas in app, for a specific workload.
      cpl ps -a $APP_NAME -w $WORKLOAD_NAME
      ```
    EX
    WITH_INFO_HEADER = false

    def call
      cp.fetch_gvc!

      workloads = [config.options[:workload]] if config.options[:workload]
      workloads ||= config[:app_workloads] + config[:additional_workloads]
      workloads.each do |workload|
        cp.fetch_workload!(workload)

        result = cp.workload_get_replicas(workload, location: config[:default_location])
        result["items"].each { |replica| puts replica }
      end
    end
  end
end
