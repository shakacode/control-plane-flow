# frozen_string_literal: true

module Command
  class MaintenanceOff < Base
    NAME = "maintenance:off"
    OPTIONS = [
      app_option(required: true),
      domain_option
    ].freeze
    DESCRIPTION = "Disables maintenance mode for an app"
    LONG_DESCRIPTION = <<~DESC
      - Disables maintenance mode for an app
      - Specify the one-off workload through `one_off_workload` in the `.controlplane/controlplane.yml` file
      - Optionally specify the maintenance workload through `maintenance_workload` in the `.controlplane/controlplane.yml` file (defaults to 'maintenance')
      - Maintenance mode is only supported for domains that use path based routing mode and have a route configured for the prefix '/' on either port 80 or 443
    DESC

    def call # rubocop:disable Metrics/MethodLength
      one_off_workload = config[:one_off_workload]
      maintenance_workload = config.current[:maintenance_workload] || "maintenance"

      domain_data = if config.domain
                      cp.fetch_domain(config.domain)
                    else
                      cp.find_domain_for([one_off_workload, maintenance_workload])
                    end
      unless domain_data
        raise "Can't find domain. " \
              "Maintenance mode is only supported for domains that use path based routing mode " \
              "and have a route configured for the prefix '/' on either port 80 or 443."
      end

      domain = domain_data["name"]
      if cp.domain_workload_matches?(domain_data, one_off_workload)
        progress.puts("Maintenance mode is already disabled for app '#{config.app}'.")
        return
      end

      cp.fetch_workload!(maintenance_workload)

      # Start all other workloads
      run_cpflow_command("ps:start", "-a", config.app, "--wait")

      progress.puts

      # Switch domain workload
      step("Switching workload for domain '#{domain}' to '#{one_off_workload}'") do
        cp.set_domain_workload(domain_data, one_off_workload)

        # Give it a bit of time for the domain to update
        Kernel.sleep(30)
      end

      progress.puts

      # Stop maintenance workload
      run_cpflow_command("ps:stop", "-a", config.app, "-w", maintenance_workload, "--wait")

      progress.puts("\nMaintenance mode disabled for app '#{config.app}'.")
    end
  end
end
