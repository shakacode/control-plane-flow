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
      - For the app-specific secrets policy, removes every permission held by the app identity; for `shared_secret_grants`, removes only `reveal`
      - Removes a marked per-app dictionary and exact-target unbound policy for generated review credentials, including after the opt-in is removed from a dynamically matched review-app entry
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
      return handle_missing_app if cp.fetch_gvc.nil?

      check_volumesets
      check_images
      return unless confirm_delete(config.app)

      # Snapshot policy state before the pre-deletion hook, so config errors surface
      # before hook side effects while the hook can still use bound shared secrets.
      policy_unbinds = secret_policy_unbinds
      run_pre_deletion_hook unless config.options[:skip_pre_deletion_hook]
      unbind_identity_from_policy(policy_unbinds)
      delete_app_resources
    end

    def handle_missing_app
      progress.puts("App '#{config.app}' does not exist.")
      cleanup_state = disposable_review_secret_cleanup_state
      return if cleanup_state == :none
      if cleanup_state == :unsafe
        raise "Review app secret resources have unexpected ownership, grants, or target; leaving them for inspection."
      end
      return unless confirm_delete("disposable secrets for app #{config.app}")

      delete_generated_review_secret_resources
    end

    def disposable_review_secret_cleanup_state
      names = config.disposable_review_secret_resource_names
      return :none unless names

      secret_name, policy_name = names
      policy = cp.fetch_policy(policy_name)
      secret = cp.fetch_secret(secret_name)
      return :none if policy.nil? && secret.nil?
      return :safe if safe_disposable_review_secret_resources?(policy, secret, secret_name)

      :unsafe
    end

    def safe_disposable_review_secret_resources?(policy, secret, secret_name)
      return generated_review_secret?(secret, secret_name) if policy.nil?

      disposable_review_secret_policy?(policy, secret_name) &&
        (secret.nil? || generated_review_secret?(secret, secret_name))
    end

    def delete_app_resources
      delete_volumesets
      delete_gvc
      delete_images
      delete_generated_review_secret_resources
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

    def delete_generated_review_secret_resources
      names = config.disposable_review_secret_resource_names
      return unless names

      secret_name, policy_name = names

      policy = cp.fetch_policy(policy_name)
      secret = cp.fetch_secret(secret_name)
      return delete_generated_review_secret_without_policy(secret, secret_name) if policy.nil?

      delete_generated_review_secret_with_policy(policy, secret, secret_name, policy_name)
    end

    def delete_generated_review_secret_without_policy(secret, secret_name)
      return if secret.nil?
      return warn_unexpected_review_secret_resources unless generated_review_secret?(secret, secret_name)

      step("Deleting orphaned disposable review app secret dictionary") { cp.delete_secret(secret_name) }
    end

    def delete_generated_review_secret_with_policy(policy, secret, secret_name, policy_name)
      return warn_unexpected_review_secret_resources unless disposable_review_secret_policy?(policy, secret_name)

      if secret
        return warn_unexpected_review_secret_resources unless generated_review_secret?(secret, secret_name)

        step("Deleting disposable review app secret dictionary") { cp.delete_secret(secret_name) }
      end
      step("Deleting disposable review app secret policy") { cp.delete_policy(policy_name) }
    end

    def generated_review_secret?(secret, secret_name)
      secret["name"] == secret_name && secret["type"] == "dictionary" &&
        generated_review_app_tag(secret) == config.app
    end

    def warn_unexpected_review_secret_resources
      progress.puts("Review app secret resources have unexpected ownership, grants, or target; " \
                    "leaving secret resources for inspection.")
    end

    def disposable_review_secret_policy?(policy, secret_name)
      generated_review_secret_policy?(policy, secret_name) && Array(policy["bindings"]).empty?
    end

    def generated_review_secret_policy?(policy, secret_name)
      policy_targets_secret?(policy, secret_name) &&
        generated_review_app_tag(policy) == config.app &&
        %w[target targetQuery gvc].all? { |key| policy[key].nil? }
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

    def unbind_identity_from_policy(policy_unbinds)
      policy_unbinds.each do |policy_unbind|
        unbind_identity_from_secret_policy(policy_unbind)
      end
    end

    def secret_policy_unbinds
      return [] if cp.fetch_identity(config.identity).nil?

      [
        app_secret_policy_unbind,
        disposable_review_secret_policy_unbind,
        *shared_secret_policy_unbinds
      ].compact
    end

    def app_secret_policy_unbind
      policy_unbind_for(
        config.secrets_policy,
        "Unbinding identity from policy for app '#{config.app}'"
      )
    end

    def disposable_review_secret_policy_unbind
      names = config.disposable_review_secret_resource_names
      return unless names && names.last != config.secrets_policy

      secret_name, policy_name = names
      policy = verified_disposable_review_secret_policy(secret_name, policy_name)
      return unless policy

      policy_unbind_for(policy_name, "Unbinding identity from disposable review app policy '#{policy_name}'", policy)
    end

    def verified_disposable_review_secret_policy(secret_name, policy_name)
      secret = cp.fetch_secret(secret_name)
      return unless secret && generated_review_secret?(secret, secret_name)

      policy = cp.fetch_policy(policy_name)
      return unless policy && generated_review_secret_policy?(policy, secret_name)

      policy
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

      # cpflow only grants reveal on shared policies, so that is the only
      # permission we remove from shared grants during cleanup.
      return unless identity_bound_to_policy_with_reveal?(policy)

      unless shared_secret_policy_targets_secret?(grant, policy)
        # A drifted shared policy should not block teardown. Remove the app
        # identity's reveal binding anyway so reusing the app name cannot inherit access.
        warn_shared_secret_policy_target_mismatch(grant, policy_name)
      end

      shared_secret_policy_unbind_data(policy_name)
    end

    def shared_secret_policy_unbind_data(policy_name)
      {
        policy_name: policy_name,
        message: "Unbinding identity from shared secret policy '#{policy_name}' for app '#{config.app}'",
        permissions: ["reveal"]
      }
    end

    def warn_shared_secret_policy_target_mismatch(grant, policy_name)
      progress.puts(
        "Warning: unbinding identity from shared secret policy '#{policy_name}' even though it does not " \
        "target configured secret '#{grant.fetch(:secret_name)}'."
      )
    end

    def policy_unbind_for(policy_name, message, policy = nil)
      policy ||= cp.fetch_policy(policy_name)
      return if policy.nil?

      permissions = identity_policy_permissions(policy)
      return if permissions.empty?

      {
        policy_name: policy_name,
        message: message,
        permissions: permissions
      }
    end

    def unbind_identity_from_secret_policy(policy_unbind)
      policy_unbind.fetch(:permissions).each do |permission|
        step("#{policy_unbind.fetch(:message)} (#{permission})") do
          cp.unbind_identity_from_policy(
            config.identity_link,
            policy_unbind.fetch(:policy_name),
            permission: permission
          )
        end
      end
    end

    def run_pre_deletion_hook
      pre_deletion_hook = config.current.dig(:hooks, :pre_deletion)
      return unless pre_deletion_hook

      run_command_in_latest_image(pre_deletion_hook, title: "pre-deletion hook")
    end
  end
end
