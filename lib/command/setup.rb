# frozen_string_literal: true

module Command
  class Setup < Base
    NAME = "setup"
    USAGE = "setup TEMPLATE [TEMPLATE] ... [TEMPLATE]"
    REQUIRES_ARGS = true
    OPTIONS = [
      app_option(required: true)
    ].freeze
    DESCRIPTION = "Applies application-specific configs from templates"
    LONG_DESCRIPTION = <<~DESC
      - Applies application-specific configs from templates (e.g., for every review-app)
      - Publishes (creates or updates) those at Control Plane infrastructure
      - Picks templates from the `.controlplane/templates` directory
      - Templates are ordinary Control Plane templates but with variable preprocessing

      **Preprocessed template variables:**

      ```
      APP_GVC      - basically GVC or app name
      APP_LOCATION - default location
      APP_ORG      - organization
      APP_IMAGE    - will use latest app image
      ```
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Applies single template.
      cpl setup redis -a $APP_NAME

      # Applies several templates (practically creating full app).
      cpl setup gvc postgres redis rails -a $APP_NAME
      ```
    EX

    def call
      config.args.each do |template|
        filename = "#{config.app_cpln_dir}/templates/#{template}.yml"
        ensure_template!(template, filename)
        apply_template(filename)
        progress.puts(template)
      end
    end

    private

    def ensure_template!(template, filename)
      Shell.abort("Can't find template '#{template}' at '#{filename}', please create it.") unless File.exist?(filename)
    end

    def apply_template(filename)
      data = File.read(filename)
                 .gsub("APP_GVC", config.app)
                 .gsub("APP_LOCATION", config[:default_location])
                 .gsub("APP_ORG", config.org)
                 .gsub("APP_IMAGE", latest_image)

      cp.apply(YAML.safe_load(data))
    end
  end
end
