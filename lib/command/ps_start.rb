# frozen_string_literal: true

module Command
  class PsStart < Base
    NAME = "ps:start"
    OPTIONS = [
      app_option(required: true),
      workload_option
    ].freeze
    DESCRIPTION = "Starts workloads in app"
    LONG_DESCRIPTION = <<~HEREDOC
      - Starts workloads in app
    HEREDOC
    EXAMPLES = <<~HEREDOC
      ```sh
      # Starts all workloads in app.
      cpl ps:start -a $APP_NAME

      # Starts a specific workload in app.
      cpl ps:start -a $APP_NAME -w $WORKLOAD_NAME
      ```
    HEREDOC

    def call
      workloads = [config.options[:workload]] if config.options[:workload]
      workloads ||= config[:app_workloads] + config[:additional_workloads]

      workloads.reverse_each do |workload|
        cp.workload_set_suspend(workload, false)
        progress.puts "#{workload} started"
      end
    end
  end
end
