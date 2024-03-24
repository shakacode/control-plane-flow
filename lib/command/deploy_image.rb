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
      - Optionally runs a release script before deploying if specified through `release_script` in the `.controlplane/controlplane.yml` file and `--run-release-phase` is provided
      - The deploy will fail if the release script exits with a non-zero code or doesn't exist
    DESC

    def call # rubocop:disable Metrics/MethodLength
      run_release_script if config.options[:run_release_phase]

      deployed_endpoints = {}

      image = latest_image

      config[:app_workloads].each do |workload|
        workload_data = cp.fetch_workload!(workload)
        workload_data.dig("spec", "containers").each do |container|
          next unless container["image"].match?(%r{^/org/#{config.org}/image/#{config.app}:})

          container_name = container["name"]
          step("Deploying image '#{image}' for workload '#{container_name}'") do
            cp.workload_set_image_ref(workload, container: container_name, image: image)
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

    def run_release_script
      release_script_name = config[:release_script]
      release_script_path = ".controlplane/#{release_script_name}"

      raise "Can't find release script in '#{release_script_path}'." unless File.exist?(release_script_path)

      progress.puts("Running release script...\n\n")

      cloned_config = config.clone
      cloned_config.options = cloned_config.options.to_h
      cloned_config.options[:image] = 'latest'
      cloned_config.args = [ release_script_path ]
      Command::Run.new(cloned_config).call

      progress.puts("Finished running release script...\n\n")
    end
  end
end
