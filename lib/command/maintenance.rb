# frozen_string_literal: true

module Command
  class Maintenance < Base
    NAME = "maintenance"
    OPTIONS = [
      app_option(required: true),
      domain_option
    ].freeze
    DESCRIPTION = "Checks if maintenance mode is on or off for an app"
    LONG_DESCRIPTION = <<~DESC
      - Checks if maintenance mode is on or off for an app
      - Outputs 'on' or 'off'
      - Specify the one-off workload through `one_off_workload` in the `.controlplane/controlplane.yml` file
      - Optionally specify the maintenance workload through `maintenance_workload` in the `.controlplane/controlplane.yml` file (defaults to 'maintenance')
      - Maintenance mode is only supported for domains that use path based routing mode and have a route configured for the prefix '/' on either port 80 or 443
    DESC
    WITH_INFO_HEADER = false

    def call
      puts maintenance_mode.enabled? ? "on" : "off"
    end

    private

    def maintenance_mode
      @maintenance_mode ||= MaintenanceMode.new(self)
    end
  end
end
