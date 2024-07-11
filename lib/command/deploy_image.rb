# frozen_string_literal: true

module Command
  class DeployImage < Base
    NAME = "deploy-image"
    OPTIONS = [
      app_option(required: true),
      run_release_phase_option
    ].freeze
    DESCRIPTION = "Deploys the latest image to app workloads, and runs a release script (optional)"
    LONG_DESCRIPTION = <<~DESC
      - Deploys the latest image to app workloads
      - Runs a release script before deploying if `release_script` is specified in the `.controlplane/controlplane.yml` file and `--run-release-phase` is provided
      - The release script is run in the context of `cpflow run` with the latest image
      - If the release script exits with a non-zero code, the command will stop executing and also exit with a non-zero code
    DESC

    def call # rubocop:disable Metrics/MethodLength
      run_release_script if config.options[:run_release_phase]

      deployed_endpoints = {}

      image = cp.latest_image
      if cp.fetch_image_details(image).nil?
        raise "Image '#{image}' does not exist in the Docker repository on Control Plane " \
              "(see https://console.cpln.io/console/org/#{config.org}/repository/#{config.app}). " \
              "Use `cpflow build-image` first."
      end

      config[:app_workloads].each do |workload|
        workload_data = cp.fetch_workload!(workload)
        workload_data.dig("spec", "containers").each do |container|
          next unless container["image"].match?(%r{^/org/#{config.org}/image/#{config.app}:})

          container_name = container["name"]
          step("Deploying image '#{image}' for workload '#{container_name}'") do
            cp.workload_set_image_ref(workload, container: container_name, image: image)
            deployed_endpoints[container_name] = endpoint_for_workload(workload_data)
          end
        end
      end

      progress.puts("\nDeployed endpoints:")
      deployed_endpoints.each do |workload, endpoint|
        progress.puts("  - #{workload}: #{endpoint}")
      end
    end

    private

    def endpoint_for_workload(workload_data)
      endpoint = workload_data.dig("status", "endpoint")
      Resolv.getaddress(endpoint.split("/").last)
      endpoint
    rescue Resolv::ResolvError
      deployments = cp.fetch_workload_deployments(workload_data["name"])
      deployments.dig("items", 0, "status", "endpoint")
    end

    def run_release_script
      release_script = config[:release_script]
      run_command_in_latest_image(release_script, title: "release script")
    end
  end
end
