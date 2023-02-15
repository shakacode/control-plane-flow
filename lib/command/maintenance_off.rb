# frozen_string_literal: true

module Command
  class MaintenanceOff < Base
    NAME = "maintenance:off"
    OPTIONS = [
      app_option(required: true)
    ].freeze
    DESCRIPTION = "Disables maintenance mode for an app"
    LONG_DESCRIPTION = <<~DESC
      - Disables maintenance mode for an app
      - Specify the one-off workload through `one_off_workload` in the `.controlplane/controlplane.yml` file
      - Specify the maintenance workload through `maintenance_workload` in the `.controlplane/controlplane.yml` file
      - Specify the domain through `domain` in the `.controlplane/controlplane.yml` file
      - Maintenance mode is only supported for domains that use path based routing mode and have a route configured for the prefix '/' on either port 80 or 443
    DESC

    def call # rubocop:disable Metrics/MethodLength
      one_off_workload = config[:one_off_workload]
      maintenance_workload = config[:maintenance_workload]
      domain = config[:domain]

      cp.fetch_workload!(maintenance_workload)

      # Start all other workloads
      perform("cpl ps:start -a #{config.app} --wait-for-ready")

      progress.puts

      # Switch domain workload
      step("Switching workload for domain '#{domain}' to '#{one_off_workload}'") do
        cp.domain_set_workload(domain, one_off_workload)

        # Give it a bit of time for the domain to update
        sleep 30
      end

      progress.puts

      # Stop maintenance workload
      perform("cpl ps:stop -a #{config.app} -w #{maintenance_workload} --wait-for-not-ready")

      progress.puts("\nMaintenance mode disabled for app '#{config.app}'.")
    end
  end
end
