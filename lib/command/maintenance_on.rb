# frozen_string_literal: true

module Command
  class MaintenanceOn < Base
    NAME = "maintenance:on"
    OPTIONS = [
      app_option(required: true),
      domain_option
    ].freeze
    DESCRIPTION = "Enables maintenance mode for an app"
    LONG_DESCRIPTION = <<~DESC
      - Enables maintenance mode for an app
      - Specify the one-off workload through `one_off_workload` in the `.controlplane/controlplane.yml` file
      - Optionally specify the maintenance workload through `maintenance_workload` in the `.controlplane/controlplane.yml` file (defaults to 'maintenance')
      - Maintenance mode is only supported for domains that use path based routing mode and have a route configured for the prefix '/' on either port 80 or 443
    DESC

    def call
      maintenance_mode.enable!
    end

    private

    def maintenance_mode
      @maintenance_mode ||= ::MaintenanceMode.new(self)
    end
  end
end
