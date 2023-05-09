# frozen_string_literal: true

module Command
  class MaintenanceSetPage < Base
    NAME = "maintenance:set-page"
    USAGE = "maintenance:set-page PAGE_URL"
    REQUIRES_ARGS = true
    OPTIONS = [
      app_option(required: true)
    ].freeze
    DESCRIPTION = "Sets the page for maintenance mode"
    LONG_DESCRIPTION = <<~DESC
      - Sets the page for maintenance mode
      - Only works if the maintenance workload uses the `shakacode/maintenance-mode` image
      - Will set the URL as an env var `PAGE_URL` on the maintenance workload
      - Specify the maintenance workload through `maintenance_workload` in the `.controlplane/controlplane.yml` file
    DESC

    def call
      maintenance_workload = config[:maintenance_workload]

      maintenance_workload_data = cp.fetch_workload!(maintenance_workload)
      maintenance_workload_data.dig("spec", "containers").each do |container|
        next unless container["image"].match?(%r{^shakacode/maintenance-mode})

        container_name = container["name"]
        page_url = config.args.first
        step("Setting '#{page_url}' as the page for maintenance mode") do
          cp.workload_set_env_var(maintenance_workload, container: container_name, name: "PAGE_URL", value: page_url)
        end
      end
    end
  end
end
