# frozen_string_literal: true

module Command
  class Ps < Base
    NAME = "ps"
    OPTIONS = [
      app_option(required: true),
      workload_option
    ].freeze
    DESCRIPTION = "Shows running replicas in app"
    LONG_DESCRIPTION = <<~HEREDOC
      - Shows running replicas in app
    HEREDOC
    EXAMPLES = <<~HEREDOC
      ```sh
      # Shows running replicas in app, for all workloads.
      cpl ps -a $APP_NAME

      # Shows running replicas in app, for a specific workload.
      cpl ps -a $APP_NAME -w $WORKLOAD_NAME
      ```
    HEREDOC

    def call # rubocop:disable Metrics/MethodLength
      workloads = [config.options[:workload]] if config.options[:workload]
      workloads ||= config[:app_workloads] + config[:additional_workloads]

      workloads.each do |workload|
        result = cp.workload_get_replicas(workload, location: config[:default_location])
        if result.nil?
          puts "#{workload}: no workload"
        elsif result["items"].nil?
          puts "#{workload}: no replicas"
        else
          result["items"].each { |replica| puts replica }
        end
      end
    end
  end
end
