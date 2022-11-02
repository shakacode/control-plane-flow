# frozen_string_literal: true

module Command
  class Ps < Base
    def call
      case config.args.first
      when "start"
        all_workloads.each { cp.set_workload_suspend(_1, false) }
      when "stop"
        all_workloads.each { cp.set_workload_suspend(_1, true) }
      else
        abort("ERROR: Unknown ps args")
      end
    end

    private

    def all_workloads
      config[:app_workloads] + config[:additional_workloads]
    end
  end
end
