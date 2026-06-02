# frozen_string_literal: true

require "resolv"

module Command
  class DeployImage < Base
    NAME = "deploy-image"
    OPTIONS = [
      app_option(required: true),
      run_release_phase_option,
      use_digest_image_ref_option
    ].freeze
    DESCRIPTION = "Deploys the latest image to app workloads, and runs a release script (optional)"
    LONG_DESCRIPTION = <<~DESC
      - Deploys the latest image to app workloads
      - Runs a release script before deploying if `release_script` is specified in the `.controlplane/controlplane.yml` file and `--run-release-phase` is provided
      - The release script is run in the context of `cpflow run` with the latest image
      - If the release script exits with a non-zero code, the command will stop executing and also exit with a non-zero code
      - If `use_digest_image_ref` is `true` in the `.controlplane/controlplane.yml` file or `--use-digest-image-ref` option is provided, deployed image's reference will include its digest
      - Repairs missing `shared_secret_grants` policy bindings before running a release phase or updating workloads
    DESC

    def call
      release_script = release_script_to_run
      image = resolve_image_to_deploy
      shared_secret_policy_grants = resolve_shared_secret_policy_grants
      workload_data_by_name = app_workload_data

      bind_shared_secret_policy_grants(shared_secret_policy_grants)
      run_release_script(release_script) if release_script
      deploy_image_to_workloads(image, workload_data_by_name)
    end

    private

    def app_workload_data
      config[:app_workloads].to_h do |workload|
        [workload, cp.fetch_workload!(workload)]
      end
    end

    def deploy_image_to_workloads(image, workload_data_by_name) # rubocop:disable Metrics/MethodLength
      deployed_endpoints = {}

      workload_data_by_name.each do |workload, workload_data|
        workload_data.dig("spec", "containers").each do |container|
          next unless container["image"].match?(%r{^/org/#{config.org}/image/#{config.app}[:@]})

          container_name = container["name"]
          step("Deploying image '#{image}' for workload '#{workload}'") do
            cp.workload_set_image_ref(workload, container: container_name, image: image)
            deployed_endpoints[workload] = endpoint_for_workload(workload_data)
          end
          # Deploy the first matching app-image container per workload; CPLN workloads
          # are expected to have a single container that runs the app image.
          break
        end
      end

      progress.puts("\nDeployed endpoints:")
      deployed_endpoints.each do |workload, endpoint|
        progress.puts("  - #{workload}: #{endpoint}")
      end
    end

    def resolve_image_to_deploy
      image = cp.latest_image
      # Preserve the pre-existing fail-fast check so missing images are reported
      # before workloads are touched.
      image_details = fetch_image_details!(image)

      return image unless config.use_digest_image_ref?

      # Control Plane accepts the tagged digest form returned here; latest_image currently returns app:N.
      "#{image}@#{image_digest!(image, image_details)}"
    end

    def fetch_image_details!(image)
      image_details = cp.fetch_image_details(image)
      raise image_not_found_message(image) if image_details.nil?

      image_details
    end

    def image_digest!(image, image_details)
      digest = image_details["digest"]
      raise "Image '#{image}' does not have a digest available." if digest.nil? || digest.empty?
      # SHA-256 only; expand the regex if Control Plane ever returns sha512 or other digest algorithms.
      # OCI digests are always lowercase hex per the OCI image spec.
      raise "Unexpected digest format for image '#{image}'." unless digest.match?(/\Asha256:[a-f0-9]{64}\z/)

      digest
    end

    def image_not_found_message(image)
      "Image '#{image}' does not exist in the Docker repository on Control Plane " \
        "(see https://console.cpln.io/console/org/#{config.org}/repository/#{config.app}). " \
        "Use `cpflow build-image` first."
    end

    def endpoint_for_workload(workload_data)
      endpoint = workload_data.dig("status", "endpoint")
      Resolv.getaddress(endpoint.split("/").last)
      endpoint
    rescue Resolv::ResolvError
      deployments = cp.fetch_workload_deployments(workload_data["name"])
      deployments.dig("items", 0, "status", "endpoint")
    end

    def release_script_to_run
      return unless config.options[:run_release_phase]

      release_script = config[:release_script]
      return release_script if release_script.is_a?(String) && !release_script.strip.empty?

      raise "release_script must be configured when --run-release-phase is provided."
    end

    def run_release_script(release_script)
      run_command_in_latest_image(release_script, title: "release script")
    end
  end
end
