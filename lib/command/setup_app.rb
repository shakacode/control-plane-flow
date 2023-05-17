# frozen_string_literal: true

module Command
  class SetupApp < Base
    NAME = "setup-app"
    OPTIONS = [
      app_option(required: true)
    ].freeze
    DESCRIPTION = "Creates an app and all its workloads"
    LONG_DESCRIPTION = <<~DESC
      - Creates an app and all its workloads
      - Specify the templates for the app and workloads through `setup` in the `.controlplane/controlplane.yml` file
      - This should should only be used for temporary apps like review apps, never for persistent apps like production (to update workloads for those, use 'cpl apply-template' instead)
    DESC

    def call
      templates = config[:setup]

      app = cp.fetch_gvc
      if app
        raise "App '#{config.app}' already exists. If you want to update this app, " \
              "either run 'cpl delete -a #{config.app}' and then re-run this command, " \
              "or run 'cpl apply-template #{templates.join(' ')} -a #{config.app}'."
      end

      Cpl::Cli.start(["apply-template", *templates, "-a", config.app])
    end
  end
end
