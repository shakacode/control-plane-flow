# frozen_string_literal: true

module Command
  class SetupApp < Base
    NAME = "setup-app"
    OPTIONS = [
      app_option(required: true),
      skip_secret_access_binding_option,
      skip_secrets_setup_option,
      skip_post_creation_hook_option
    ].freeze
    DESCRIPTION = "Creates an app and all its workloads"
    LONG_DESCRIPTION = <<~DESC
      - Creates an app and all its workloads
      - Specify the templates for the app and workloads through `setup_app_templates` in the `.controlplane/controlplane.yml` file
      - This should only be used for temporary apps like review apps, never for persistent apps like production or staging (to update workloads for those, use 'cpl apply-template' instead)
      - Configures app to have org-level secrets with default name "{APP_PREFIX}-secrets"
        using org-level policy with default name "{APP_PREFIX}-secrets-policy" (names can be customized, see docs)
      - Creates identity for secrets if it does not exist
      - Use `--skip-secrets-setup` to prevent the automatic setup of secrets,
        or set it through `skip_secrets_setup` in the `.controlplane/controlplane.yml` file
      - Runs a post-creation hook after the app is created if `hooks.post_creation` is specified in the `.controlplane/controlplane.yml` file
      - If the hook exits with a non-zero code, the command will stop executing and also exit with a non-zero code
      - Use `--skip-post-creation-hook` to skip the hook if specified in `controlplane.yml`
    DESC
    VALIDATIONS = %w[config templates].freeze

    def call # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength
      templates = config[:setup_app_templates]

      app = cp.fetch_gvc
      if app
        raise "App '#{config.app}' already exists. If you want to update this app, " \
              "either run 'cpl delete -a #{config.app}' and then re-run this command, " \
              "or run 'cpl apply-template #{templates.join(' ')} -a #{config.app}'."
      end

      skip_secrets_setup = config.options[:skip_secret_access_binding] ||
                           config.options[:skip_secrets_setup] || config.current[:skip_secrets_setup]

      create_secret_and_policy_if_not_exist unless skip_secrets_setup

      args = []
      args.push("--add-app-identity") unless skip_secrets_setup
      Cpl::Cli.start(["apply-template", *templates, "-a", config.app, *args])

      bind_identity_to_policy unless skip_secrets_setup
      run_post_creation_hook unless config.options[:skip_post_creation_hook]
    end

    private

    def create_secret_and_policy_if_not_exist
      create_secret_if_not_exists
      create_policy_if_not_exists

      progress.puts
    end

    def create_secret_if_not_exists
      if cp.fetch_secret(config.secrets)
        progress.puts("Secret '#{config.secrets}' already exists. Skipping creation...")
      else
        step("Creating secret '#{config.secrets}'") do
          cp.apply_hash(build_secret_hash)
        end
      end
    end

    def create_policy_if_not_exists
      if cp.fetch_policy(config.secrets_policy)
        progress.puts("Policy '#{config.secrets_policy}' already exists. Skipping creation...")
      else
        step("Creating policy '#{config.secrets_policy}'") do
          cp.apply_hash(build_policy_hash)
        end
      end
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
      {
        "kind" => "policy",
        "name" => config.secrets_policy,
        "targetKind" => "secret",
        "targetLinks" => ["//secret/#{config.secrets}"]
      }
    end

    def bind_identity_to_policy
      progress.puts

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
