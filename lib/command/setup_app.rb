# frozen_string_literal: true

module Command
  class SetupApp < Base
    NAME = "setup-app"
    OPTIONS = [
      app_option(required: true),
      skip_secret_access_binding_option
    ].freeze
    DESCRIPTION = "Creates an app and all its workloads"
    LONG_DESCRIPTION = <<~DESC
      - Creates an app and all its workloads
      - Specify the templates for the app and workloads through `setup_app_templates` in the `.controlplane/controlplane.yml` file
      - This should only be used for temporary apps like review apps, never for persistent apps like production or staging (to update workloads for those, use 'cpl apply-template' instead)
      - Configures app to have org-level secrets with default name "{APP_PREFIX}-secrets"
        using org-level policy with default name "{APP_PREFIX}-secrets-policy" (names can be customized, see docs)
      - Use `--skip-secret-access-binding` to prevent the automatic setup of secrets
    DESC
    VALIDATIONS = %w[config templates].freeze

    def call
      templates = config[:setup_app_templates]

      app = cp.fetch_gvc
      if app
        raise "App '#{config.app}' already exists. If you want to update this app, " \
              "either run 'cpl delete -a #{config.app}' and then re-run this command, " \
              "or run 'cpl apply-template #{templates.join(' ')} -a #{config.app}'."
      end

      create_secret_and_policy_if_not_exist unless config.options[:skip_secret_access_binding]

      Cpl::Cli.start(["apply-template", *templates, "-a", config.app])

      bind_identity_to_policy unless config.options[:skip_secret_access_binding]
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

      if cp.fetch_identity(config.identity).nil?
        raise "Can't bind identity to policy: identity '#{config.identity}' doesn't exist. " \
              "Please create it or use `--skip-secret-access-binding` to ignore this message."
      end

      step("Binding identity '#{config.identity}' to policy '#{config.secrets_policy}'") do
        cp.bind_identity_to_policy(config.identity_link, config.secrets_policy)
      end
    end
  end
end
