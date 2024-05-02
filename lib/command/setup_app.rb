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
      - This should only be used for temporary apps like review apps, never for persistent apps like production (to update workloads for those, use 'cpl apply-template' instead)
      - Automatically binds the app to the secrets policy, as long as both the identity and the policy exist
      - Use `--skip-secret-access-binding` to prevent the automatic bind
    DESC

    def call # rubocop:disable Metrics/MethodLength
      templates = config[:setup_app_templates]

      app = cp.fetch_gvc
      if app
        raise "App '#{config.app}' already exists. If you want to update this app, " \
              "either run 'cpl delete -a #{config.app}' and then re-run this command, " \
              "or run 'cpl apply-template #{templates.join(' ')} -a #{config.app}'."
      end

      Cpl::Cli.start(["apply-template", *templates, "-a", config.app])

      return if config.options[:skip_secret_access_binding]

      progress.puts

      if cp.fetch_identity(app_identity).nil? || cp.fetch_policy(app_secrets_policy).nil?
        raise "Can't bind identity to policy: identity '#{app_identity}' or " \
              "policy '#{app_secrets_policy}' doesn't exist. " \
              "Please create them or use `--skip-secret-access-binding` to ignore this message." \
              "You can also set a custom secrets name with `secrets_name` " \
              "and a custom secrets policy name with `secrets_policy_name` " \
              "in the `.controlplane/controlplane.yml` file."
      end

      step("Binding identity to policy") do
        cp.bind_identity_to_policy(app_identity_link, app_secrets_policy)
      end
    end
  end
end
