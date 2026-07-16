# frozen_string_literal: true

require "resolv"

module Command
  class DeployImage < Base # rubocop:disable Metrics/ClassLength
    WORKLOAD_IMAGE_UPDATE_MAX_ATTEMPTS = 30
    WORKLOAD_IMAGE_UPDATE_STEP_OPTIONS = {
      retry_on_failure: true,
      max_retry_count: WORKLOAD_IMAGE_UPDATE_MAX_ATTEMPTS - 1,
      wait: 1
    }.freeze

    NAME = "deploy-image"
    OPTIONS = [
      app_option(required: true),
      workload_option(repeatable: true),
      run_release_phase_option,
      use_digest_image_ref_option
    ].freeze
    DESCRIPTION = "Deploys the latest image to app workloads, and runs a release script (optional)"
    LONG_DESCRIPTION = <<~DESC
      - Deploys the latest image to app workloads
      - Use `--workload`/`-w` one or more times to deploy only selected app workloads
      - If `deploy_order` is configured and no `--workload` is provided, deploys ordered workload groups one at a time and waits for each group to be ready before continuing
      - Workloads listed in `app_workloads` but omitted from `deploy_order` deploy last as an implicit final group
      - Runs a release script before deploying if `release_script` is specified in the `.controlplane/controlplane.yml` file and `--run-release-phase` is provided
      - The release script is run in the context of `cpflow run` with the latest image
      - If the release script exits with a non-zero code, the command will stop executing and also exit with a non-zero code
      - If `use_digest_image_ref` is `true` in the `.controlplane/controlplane.yml` file or `--use-digest-image-ref` option is provided, deployed image's reference will include its digest
      - Repairs missing `shared_secret_grants` policy bindings before running a release phase or updating workloads
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Deploys the latest image to all app workloads.
      cpflow deploy-image -a $APP_NAME

      # Deploys only one app workload.
      cpflow deploy-image -a $APP_NAME -w node-renderer

      # Deploys only selected app workloads.
      cpflow deploy-image -a $APP_NAME -w node-renderer -w sidekiq
      ```
    EX

    def call
      release_script = release_script_to_run
      image = resolve_image_to_deploy
      shared_secret_policy_grant_pairs = resolve_shared_secret_policy_grants
      workload_data_by_name = app_workload_data(workload_names_to_deploy)

      bind_shared_secret_policy_grants(shared_secret_policy_grant_pairs)
      run_release_script(release_script) if release_script
      deploy_image(image, workload_data_by_name)
    end

    private

    def workload_names_to_deploy
      app_workloads = config[:app_workloads]
      requested_workloads = requested_workload_names
      return app_workloads if requested_workloads.empty?

      ensure_workloads_configured!(requested_workloads, app_workloads)
      requested_workloads
    end

    def ensure_workloads_configured!(requested_workloads, app_workloads)
      requested_workloads.each do |workload|
        next if app_workloads.include?(workload)

        raise "Workload '#{workload}' must be listed in app_workloads for app '#{config.app}'."
      end
    end

    def app_workload_data(workloads)
      workloads.to_h do |workload|
        [workload, cp.fetch_workload!(workload)]
      end
    end

    def deploy_image(image, workload_data_by_name)
      deployed_endpoints = {}

      if deploy_in_order?
        deploy_image_to_ordered_workloads(image, workload_data_by_name, deployed_endpoints)
      else
        deployed_endpoints.merge!(deploy_image_to_workloads(image, workload_data_by_name))
      end
    ensure
      print_deployed_endpoints(deployed_endpoints)
    end

    def deploy_in_order?
      requested_workload_names.empty? && config.deploy_order
    end

    def deployment_groups(workload_data_by_name)
      ordered_groups = config.deploy_order
      ordered_workloads = ordered_groups.flatten
      unordered_workloads = workload_data_by_name.keys - ordered_workloads

      [*ordered_groups, unordered_workloads].reject(&:empty?)
    end

    def deploy_image_to_ordered_workloads(image, workload_data_by_name, deployed_endpoints)
      deployment_groups(workload_data_by_name).each do |group|
        deployed_endpoints.merge!(deploy_image_to_workloads(image, workload_data_by_name.slice(*group)))
        wait_for_workloads_ready(group)
      end
    end

    def requested_workload_names
      @requested_workload_names ||= Array(config.options[:workload]).map(&:to_s).uniq
    end

    def deploy_image_to_workloads(image, workload_data_by_name) # rubocop:disable Metrics/MethodLength
      deployed_endpoints = {}

      workload_data_by_name.each do |workload, workload_data|
        workload_data.dig("spec", "containers").each do |container|
          next unless container["image"].match?(%r{^/org/#{config.org}/image/#{config.app}[:@]})

          container_name = container["name"]
          step("Deploying image '#{image}' for workload '#{workload}'", **WORKLOAD_IMAGE_UPDATE_STEP_OPTIONS) do
            updated = cp.workload_set_image_ref(workload, container: container_name, image: image)
            next false unless updated

            deployed_endpoints[workload] = endpoint_for_workload(workload_data)
          end
          # Deploy the first matching app-image container per workload; CPLN workloads
          # are expected to have a single container that runs the app image.
          break
        end
      end

      deployed_endpoints
    end

    def print_deployed_endpoints(deployed_endpoints)
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
