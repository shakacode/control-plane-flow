# frozen_string_literal: true

module Command
  class MaintenanceOn < Base
    NAME = "maintenance:on"
    OPTIONS = [
      app_option(required: true)
    ].freeze
    DESCRIPTION = "Enables maintenance mode for an app"
    LONG_DESCRIPTION = <<~DESC
      - Enables maintenance mode for an app
      - Specify the maintenance workload through `maintenance_workload` in the `.controlplane/controlplane.yml` file
      - Specify the domain through `domain` in the `.controlplane/controlplane.yml` file
      - Maintenance mode is only supported for domains that use path based routing mode and have a route configured for the prefix '/' on either port 80 or 443
    DESC

    def call # rubocop:disable Metrics/MethodLength
      maintenance_workload = config[:maintenance_workload]
      domain = config[:domain]

      cp.fetch_workload!(maintenance_workload)

      # Start maintenance workload
      perform("cpl ps:start -a #{config.app} -w #{maintenance_workload} --wait-for-ready")

      progress.puts

      # Switch domain workload
      step("Switching workload for domain '#{domain}' to '#{maintenance_workload}'") do
        cp.domain_set_workload(domain, maintenance_workload)

        # Give it a bit of time for the domain to update
        sleep 30
      end

      progress.puts

      # Stop all other workloads
      perform("cpl ps:stop -a #{config.app} --wait-for-not-ready")

      progress.puts("\nMaintenance mode enabled for app '#{config.app}'.")
    end
  end
end
