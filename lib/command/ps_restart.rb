# frozen_string_literal: true

module Command
  class PsRestart < Base
    NAME = "ps:restart"
    OPTIONS = [
      app_option(required: true),
      workload_option
    ].freeze
    DESCRIPTION = "Forces redeploy of workloads in app"
    LONG_DESCRIPTION = <<~DESC
      - Forces redeploy of workloads in app
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Forces redeploy of all workloads in app.
      cpflow ps:restart -a $APP_NAME

      # Forces redeploy of a specific workload in app.
      cpflow ps:restart -a $APP_NAME -w $WORKLOAD_NAME
      ```
    EX

    def call
      workloads = [config.options[:workload]] if config.options[:workload]
      workloads ||= config[:app_workloads] + config[:additional_workloads]

      workloads.each do |workload|
        step("Restarting workload '#{workload}'") do
          cp.fetch_workload!(workload)

          cp.workload_force_redeployment(workload)
        end
      end
    end
  end
end
