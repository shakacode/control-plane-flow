# frozen_string_literal: true

module Command
  class DeployImage < Base
    NAME = "deploy-image"
    OPTIONS = [
      app_option(required: true)
    ].freeze
    DESCRIPTION = "Deploys the latest image to app workloads"
    LONG_DESCRIPTION = <<~DESC
      - Deploys the latest image to app workloads
    DESC

    def call # rubocop:disable Metrics/MethodLength
      deployed_endpoints = {}

      image = latest_image

      config[:app_workloads].each do |workload|
        workload_data = dry_run? ? workload_date_for_dry_run : cp.fetch_workload!(workload)

        workload_data.dig("spec", "containers").each do |container|
          next unless container["image"].match?(%r{^/org/#{config.org}/image/#{config.app}:})

          container_name = container["name"]

          show_dry_run_message("ControlPlane - workload set image ref") if dry_run?
          step("Deploying image '#{image}' for workload '#{container_name}'") do
            cp.workload_set_image_ref(workload, container: container_name, image: image) unless dry_run?
            deployed_endpoints[container_name] = workload_data.dig("status", "endpoint")
          end
        end
      end

      progress.puts("\nDeployed endpoints:")
      deployed_endpoints.each do |workload, endpoint|
        progress.puts("  - #{workload}: #{endpoint}")
      end
    end

    private

    def workload_date_for_dry_run
      {
        "spec" => {
          "containers" => [
            {
              "name" => "DRY-WORKLOAD",
              "image" => "/org/#{config.org}/image/#{config.app}:12345"
            }
          ]
        },
        "status" => {
          "endpoint" => "DRY-ENDPOINT"
        }
      }
    end
  end
end
