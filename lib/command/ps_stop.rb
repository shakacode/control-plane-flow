# frozen_string_literal: true

module Command
  class PsStop < Base
    def call
      workloads = [config.options[:workload]] if config.options[:workload]
      workloads ||= config[:app_workloads] + config[:additional_workloads]

      workloads.each do |workload|
        cp.workload_set_suspend(workload, true)
        progress.puts "#{workload} stopped"
      end
    end
  end
end
