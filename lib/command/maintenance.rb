# frozen_string_literal: true

module Command
  class Maintenance < Base
    NAME = "maintenance"
    OPTIONS = [
      app_option(required: true)
    ].freeze
    DESCRIPTION = "Checks if maintenance mode is on or off for an app"
    LONG_DESCRIPTION = <<~DESC
      - Checks if maintenance mode is on or off for an app
      - Outputs 'on' or 'off'
      - Specify the maintenance workload through `maintenance_workload` in the `.controlplane/controlplane.yml` file
      - Specify the domain through `domain` in the `.controlplane/controlplane.yml` file
    DESC

    def call
      maintenance_workload = config[:maintenance_workload]
      domain = config[:domain]

      workload = cp.domain_get_workload(domain)
      if workload == maintenance_workload
        progress.puts("on")
      else
        progress.puts("off")
      end
    end
  end
end
