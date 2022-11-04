# frozen_string_literal: true

module Command
  class Logs < Base
    def call
      workload = config.options[:workload] || config[:one_off_workload]
      cp.logs(workload: workload)
    end
  end
end
