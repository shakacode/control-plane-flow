# frozen_string_literal: true

module Command
  class SetupApp < Base # rubocop:disable Metrics/ClassLength
    NAME = "setup-app"
    OPTIONS = [
      app_option(required: true),
      skip_secret_access_binding_option,
      skip_secrets_setup_option,
      skip_post_creation_hook_option,
      refresh_templates_option
    ].freeze
    DESCRIPTION = "Creates an app and all its workloads"
    LONG_DESCRIPTION = <<~DESC
      - Creates an app and all its workloads
      - Specify the templates for the app and workloads through `setup_app_templates` in the `.controlplane/controlplane.yml` file
      - Use this for temporary apps like review apps and for first-time bootstrap of persistent staging or production apps; after a persistent app exists, use 'cpflow apply-template' for template updates
      - Configures app to have org-level secrets with default name `"{APP_PREFIX}-secrets"`
        using org-level policy with default name `"{APP_PREFIX}-secrets-policy"` (names can be customized, see docs)
      - Creates identity for secrets if it does not exist
      - For dynamically named review apps with `generated_review_secret_keys`, checks an existing policy before writing credentials, creates a per-app dictionary, skips its secret template during initial setup, and fills missing disposable keys without printing or rotating values
      - Binds the app identity to any configured `shared_secret_grants` policies as part of the secrets setup flow; skipped when `--skip-secrets-setup` or `--skip-secret-access-binding` is provided, or `skip_secrets_setup` is set
      - Use `--skip-secrets-setup` to prevent the automatic setup of secrets,
        or set it through `skip_secrets_setup` in the `.controlplane/controlplane.yml` file
      - Runs a post-creation hook after the app is created if `hooks.post_creation` is specified in the `.controlplane/controlplane.yml` file
      - If the hook exits with a non-zero code, the command will stop executing and also exit with a non-zero code
      - Use `--skip-post-creation-hook` to skip the hook if specified in `controlplane.yml`
      - Use `--refresh-templates` to apply configured templates noninteractively to an existing app while preserving each workload's configured app image even when workloads are unready or use mixed image versions, skipping existing secret templates (but filling missing opt-in generated review keys), repairing secrets access bindings, and skipping the post-creation hook
    DESC
    VALIDATIONS = %w[config templates].freeze

    def call # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      templates = config[:setup_app_templates]
      refresh_templates = config.options[:refresh_templates]

      app = cp.fetch_gvc
      if app && !refresh_templates
        raise "App '#{config.app}' already exists. If you want to update this app, " \
              "either run 'cpflow delete -a #{config.app}' and then re-run this command, " \
              "or run 'cpflow apply-template #{templates.join(' ')} -a #{config.app}'."
      end
      raise "App '#{config.app}' does not exist, so its templates cannot be refreshed." if !app && refresh_templates

      skip_secrets_setup = skip_secrets_setup?

      # Validate shared grants before app resource creation so config/policy
      # drift does not leave a partially-created review app.
      shared_secret_policy_grant_pairs = resolve_shared_secret_policy_grants unless skip_secrets_setup
      create_secret_and_policy_if_not_exist unless skip_secrets_setup

      args = []
      args.push("--add-app-identity") unless skip_secrets_setup
      args.push("--yes") if refresh_templates
      args.push("--preserve-existing-runtime") if refresh_templates
      if !skip_secrets_setup && config.generated_review_secret_keys.any?
        args.push("--skip-policy-template", config.secrets_policy)
        args.push("--skip-secret-template", config.secrets) unless refresh_templates
      end
      run_cpflow_command("apply-template", *templates, "-a", config.app, *args)

      bind_identity_to_policy unless skip_secrets_setup
      bind_shared_secret_policy_grants(shared_secret_policy_grant_pairs) unless skip_secrets_setup
      run_post_creation_hook unless refresh_templates || config.options[:skip_post_creation_hook]
    end

    private

    def skip_secrets_setup?
      config.options[:skip_secret_access_binding] ||
        config.options[:skip_secrets_setup] || config.current[:skip_secrets_setup]
    end

    def create_secret_and_policy_if_not_exist
      validate_existing_generated_review_policy_before_secret!
      create_secret_if_not_exists
      create_policy_if_not_exists

      progress.puts
    end

    def validate_existing_generated_review_policy_before_secret!
      return if config.generated_review_secret_keys.empty?

      policy = cp.fetch_policy(config.secrets_policy)
      verify_generated_review_policy!(policy) if policy
    end

    def create_secret_if_not_exists
      secret = cp.fetch_secret(config.secrets)
      return existing_secret_if_any(secret) if secret

      step("Creating secret '#{config.secrets}'") { create_new_secret }
    end

    def existing_secret_if_any(secret)
      if config.generated_review_secret_keys.any? && !generated_review_secret_owned_by_app?(secret)
        raise "Existing review app secret dictionary is not owned by this app."
      end

      progress.puts("Secret '#{config.secrets}' already exists. Skipping creation...")
      fill_missing_generated_review_secrets
    end

    def generated_review_secret_owned_by_app?(secret)
      secret.is_a?(Hash) && secret["name"] == config.secrets && secret["type"] == "dictionary" &&
        generated_review_app_tag(secret) == config.app
    end

    def create_new_secret
      if config.generated_review_secret_keys.any?
        cp.create_sensitive_secret(config.secrets, generated_review_secret_data)
      else
        cp.apply_hash(build_secret_hash)
      end
    end

    def fill_missing_generated_review_secrets
      keys = config.generated_review_secret_keys
      return if keys.empty?

      data = revealed_review_secret_data

      missing_keys = keys.reject { |key| data[key].is_a?(String) && !data[key].empty? }
      return if missing_keys.empty?

      step("Adding missing generated review app secret fields") do
        cp.patch_sensitive_secret_data(config.secrets, generated_review_secret_data(missing_keys))
      end
    end

    def revealed_review_secret_data
      revealed = cp.reveal_secret(config.secrets)
      raise "Cannot safely inspect existing review app secret dictionary." unless revealed.is_a?(Hash)
      raise "Existing review app secret is not a dictionary." unless revealed["type"] == "dictionary"

      data = revealed["data"]
      raise "Cannot safely inspect existing review app secret dictionary." unless data.is_a?(Hash)

      data
    end

    def generated_review_secret_data(keys = config.generated_review_secret_keys)
      keys.to_h { |key| [key, SecureRandom.hex(32)] }
    end

    def create_policy_if_not_exists
      policy = cp.fetch_policy(config.secrets_policy)
      if policy
        verify_generated_review_policy!(policy) if config.generated_review_secret_keys.any?
        progress.puts("Policy '#{config.secrets_policy}' already exists. Skipping creation...")
      else
        step("Creating policy '#{config.secrets_policy}'") do
          cp.apply_hash(build_policy_hash)
        end
      end
    end

    def verify_generated_review_policy!(policy)
      expected_target = policy_targets_secret?(policy, config.secrets)
      owned_policy = generated_review_app_tag(policy) == config.app
      no_extra_selectors = %w[target targetQuery gvc].all? { |key| policy[key].nil? }
      own_bindings = Array(policy["bindings"]).all? do |binding|
        Array(binding["principalLinks"]) == [config.identity_link]
      end
      return if expected_target && owned_policy && no_extra_selectors && own_bindings

      raise "Existing review app secret policy has an unexpected target or binding."
    end

    def build_secret_hash
      {
        "kind" => "secret",
        "name" => config.secrets,
        "type" => "dictionary",
        "data" => {}
      }
    end

    def build_policy_hash
      policy = {
        "kind" => "policy",
        "name" => config.secrets_policy,
        "targetKind" => "secret",
        "targetLinks" => ["//secret/#{config.secrets}"]
      }
      policy["tags"] = { ::Config::GENERATED_REVIEW_APP_TAG => config.app } if config.generated_review_secret_keys.any?
      policy
    end

    def bind_identity_to_policy
      progress.puts

      if config.generated_review_secret_keys.any?
        policy = cp.fetch_policy(config.secrets_policy)
        raise "Cannot safely inspect review app secret policy before binding." unless policy.is_a?(Hash)

        verify_generated_review_policy!(policy)
      end

      step("Binding identity '#{config.identity}' to policy '#{config.secrets_policy}'") do
        cp.bind_identity_to_policy(config.identity_link, config.secrets_policy)
      end
    end

    def run_post_creation_hook
      post_creation_hook = config.current.dig(:hooks, :post_creation)
      return unless post_creation_hook

      run_command_in_latest_image(post_creation_hook, title: "post-creation hook")
    end
  end
end
