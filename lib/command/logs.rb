# frozen_string_literal: true

module Command
  class Logs < Base
    def call
      # FIXME: atm, using one-off org and dyno name for simplicity
      org = config.one_off[:org]
      workload = config.options[:workload] || config.one_off[:workload]

      cp = Controlplane.new(config, org: org)
      cp.show_logs(workload)
    end
  end
end
