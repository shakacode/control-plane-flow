# frozen_string_literal: true

module Command
  class Delete < Base # rubocop:disable Metrics/ClassLength
    NAME = "delete"
    OPTIONS = [
      app_option(required: true),
      workload_option,
      skip_confirm_option,
      skip_pre_deletion_hook_option
    ].freeze
    DESCRIPTION = "Deletes the whole app (GVC with all workloads, all volumesets and all images) or a specific workload"
    LONG_DESCRIPTION = <<~DESC
      - Deletes the whole app (GVC with all workloads, all volumesets and all images) or a specific workload
      - Also unbinds the app from the secrets policy and any configured `shared_secret_grants` policies, as long as both the identity and each policy exist (and are bound)
      - Will ask for explicit user confirmation
      - Runs a pre-deletion hook before the app is deleted if `hooks.pre_deletion` is specified in the `.controlplane/controlplane.yml` file
      - If the hook exits with a non-zero code, the command will stop executing and also exit with a non-zero code
      - Use `--skip-pre-deletion-hook` to skip the hook if specified in `controlplane.yml`
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Deletes the whole app (GVC with all workloads, all volumesets and all images).
      cpflow delete -a $APP_NAME

      # Deletes a specific workload.
      cpflow delete -a $APP_NAME -w $WORKLOAD_NAME
      ```
    EX

    def call
      workload = config.options[:workload]
      if workload
        delete_single_workload(workload)
      else
        delete_whole_app
      end
    end

    private

    def delete_single_workload(workload)
      if cp.fetch_workload(workload).nil?
        return progress.puts("Workload '#{workload}' does not exist in app '#{config.app}'.")
      end
      return unless confirm_delete(workload)

      delete_workload(workload)
    end

    def delete_whole_app
      return progress.puts("App '#{config.app}' does not exist.") if cp.fetch_gvc.nil?

      check_volumesets
      check_images
      return unless confirm_delete(config.app)

      policy_unbinds = secret_policy_unbinds
      run_pre_deletion_hook unless config.options[:skip_pre_deletion_hook]
      unbind_identity_from_policy(policy_unbinds)
      delete_volumesets
      delete_gvc
      delete_images
    end

    def check_volumesets
      @volumesets = cp.fetch_volumesets["items"]
      return progress.puts("No volumesets to delete from app '#{config.app}'.") unless @volumesets.any?

      message = "The following volumesets will be deleted along with the app '#{config.app}':"
      volumesets_list = @volumesets.map { |volumeset| "- #{volumeset['name']}" }.join("\n")
      progress.puts("#{Shell.color(message, :red)}\n#{volumesets_list}\n\n")
    end

    def check_images
      @images = cp.query_images["items"]
                  .select { |image| image["name"].start_with?("#{config.app}:") }
      return progress.puts("No images to delete from app '#{config.app}'.") unless @images.any?

      message = "The following images will be deleted along with the app '#{config.app}':"
      images_list = @images.map { |image| "- #{image['name']}" }.join("\n")
      progress.puts("#{Shell.color(message, :red)}\n#{images_list}\n\n")
    end

    # Prompts the user and writes to progress on confirm — returns boolean but
    # has side effects, so the method name intentionally lacks `?`.
    def confirm_delete(item) # rubocop:disable Naming/PredicateMethod
      return true if config.options[:yes]

      confirmed = Shell.confirm("Are you sure you want to delete '#{item}'?")
      return false unless confirmed

      progress.puts
      true
    end

    def delete_gvc
      step("Deleting app '#{config.app}'") do
        cp.gvc_delete
      end
    end

    def delete_workload(workload)
      step("Deleting workload '#{workload}' from app '#{config.app}'") do
        cp.delete_workload(workload)
      end
    end

    def delete_volumesets
      @volumesets.each do |volumeset|
        step("Deleting volumeset '#{volumeset['name']}' from app '#{config.app}'") do
          # If the volumeset is attached to workloads, we need to delete the workloads first
          workloads = volumeset.dig("status", "workloadLinks")&.map { |workload_link| workload_link.split("/").last }
          workloads&.each { |workload| cp.delete_workload(workload) }

          cp.delete_volumeset(volumeset["name"])
        end
      end
    end

    def delete_images
      @images.each do |image|
        step("Deleting image '#{image['name']}' from app '#{config.app}'") do
          cp.image_delete(image["name"])
        end
      end
    end

    def unbind_identity_from_policy(policy_unbinds = secret_policy_unbinds)
      policy_unbinds.each do |policy_unbind|
        unbind_identity_from_secret_policy(policy_unbind)
      end
    end

    def secret_policy_unbinds
      return [] if cp.fetch_identity(config.identity).nil?

      [
        app_secret_policy_unbind,
        *shared_secret_policy_unbinds
      ].compact
    end

    def app_secret_policy_unbind
      policy_unbind_for(
        config.secrets_policy,
        "Unbinding identity from policy for app '#{config.app}'"
      )
    end

    def shared_secret_policy_unbinds
      config.shared_secret_grants.filter_map do |grant|
        shared_secret_policy_unbind(grant)
      end
    end

    def shared_secret_policy_unbind(grant)
      policy_name = grant.fetch(:policy_name)
      policy = cp.fetch_policy(policy_name)
      return if policy.nil?
      return unless identity_bound_to_policy?(policy)

      ensure_shared_secret_policy_targets_secret!(grant, policy)

      {
        policy_name: policy_name,
        message: "Unbinding identity from shared secret policy '#{policy_name}' for app '#{config.app}'"
      }
    end

    def policy_unbind_for(policy_name, message)
      policy = cp.fetch_policy(policy_name)
      return if policy.nil? || !identity_bound_to_policy?(policy)

      {
        policy_name: policy_name,
        message: message
      }
    end

    def unbind_identity_from_secret_policy(policy_unbind)
      step(policy_unbind.fetch(:message)) do
        cp.unbind_identity_from_policy(config.identity_link, policy_unbind.fetch(:policy_name))
      end
    end

    def run_pre_deletion_hook
      pre_deletion_hook = config.current.dig(:hooks, :pre_deletion)
      return unless pre_deletion_hook

      run_command_in_latest_image(pre_deletion_hook, title: "pre-deletion hook")
    end
  end
end
