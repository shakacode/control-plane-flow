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
      - Specify the one-off workload through `one_off_workload` in the `.controlplane/controlplane.yml` file
      - Optionally specify the maintenance workload through `maintenance_workload` in the `.controlplane/controlplane.yml` file (defaults to 'maintenance')
      - Maintenance mode is only supported for domains that use path based routing mode and have a route configured for the prefix '/' on either port 80 or 443
    DESC

    def call # rubocop:disable Metrics/MethodLength
      one_off_workload = config[:one_off_workload]
      maintenance_workload = config.current[:maintenance_workload] || "maintenance"

      domain_data = cp.find_domain_for([one_off_workload, maintenance_workload])
      unless domain_data
        raise "Can't find domain. " \
              "Maintenance mode is only supported for domains that use path based routing mode " \
              "and have a route configured for the prefix '/' on either port 80 or 443."
      end

      domain = domain_data["name"]
      domain_workload = cp.get_domain_workload(domain_data)
      if domain_workload == maintenance_workload
        progress.puts("Maintenance mode is already enabled for app '#{config.app}'.")
        exit
      end

      cp.fetch_workload!(maintenance_workload)

      # Start maintenance workload
      perform("cpl ps:start -a #{config.app} -w #{maintenance_workload} --wait-for-ready")

      progress.puts

      # Switch domain workload
      step("Switching workload for domain '#{domain}' to '#{maintenance_workload}'") do
        cp.set_domain_workload(domain_data, maintenance_workload)

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
