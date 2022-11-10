# frozen_string_literal: true

module Command
  class PsRestart < Base
    def call
      workloads = [config.options[:workload]] if config.options[:workload]
      workloads ||= config[:app_workloads] + config[:additional_workloads]

      workloads.each do |workload|
        cp.workload_force_redeployment(workload)
        progress.puts "#{workload} restarted"
      end
    end
  end
end
