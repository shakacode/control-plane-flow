# frozen_string_literal: true

module Command
  class Ps < Base
    NAME = "ps"
    OPTIONS = [
      app_option(required: true),
      location_option,
      workload_option
    ].freeze
    DESCRIPTION = "Shows running replicas in app"
    LONG_DESCRIPTION = <<~DESC
      - Shows running replicas in app
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Shows running replicas in app, for all workloads.
      cpflow ps -a $APP_NAME

      # Shows running replicas in app, for a specific workload.
      cpflow ps -a $APP_NAME -w $WORKLOAD_NAME
      ```
    EX
    WITH_INFO_HEADER = false

    def call
      cp.fetch_gvc!

      location = config.location

      workloads = [config.options[:workload]] if config.options[:workload]
      workloads ||= config[:app_workloads] + config[:additional_workloads]
      workloads.each do |workload|
        cp.fetch_workload!(workload)

        result = cp.fetch_workload_replicas(workload, location: location)
        result["items"].each { |replica| puts replica }
      end
    end
  end
end
