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

      domain_workload = cp.get_domain_workload(domain_data)
      if domain_workload == maintenance_workload
        puts "on"
      else
        puts "off"
      end
    end

    def puts_info_header
      # Do not print any info header
    end
  end
end
