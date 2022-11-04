# frozen_string_literal: true

module Command
  class Open < Base
    def call
      workload = config.options[:workload] || config[:one_off_workload]
      data = cp.workload_get(workload)
      url = data["status"]["endpoint"]
      opener = `which xdg-open open`.split("\n").grep_v("not found").first

      exec %(#{opener} "#{url}")
    end
  end
end
