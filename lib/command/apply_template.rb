# frozen_string_literal: true

module Command
  class ApplyTemplate < Base # rubocop:disable Metrics/ClassLength
    NAME = "apply-template"
    USAGE = "apply-template TEMPLATE [TEMPLATE] ... [TEMPLATE]"
    REQUIRES_ARGS = true
    OPTIONS = [
      app_option(required: true),
      location_option,
      skip_confirm_option
    ].freeze
    DESCRIPTION = "Applies application-specific configs from templates"
    LONG_DESCRIPTION = <<~DESC
      - Applies application-specific configs from templates (e.g., for every review-app)
      - Publishes (creates or updates) those at Control Plane infrastructure
      - Picks templates from the `.controlplane/templates` directory
      - Templates are ordinary Control Plane templates but with variable preprocessing

      **Preprocessed template variables:**

      ```
      {{APP_ORG}}           - organization name
      {{APP_NAME}}          - GVC/app name
      {{APP_LOCATION}}      - location, per YML file, ENV, or command line arg
      {{APP_LOCATION_LINK}} - full link for location, ready to be used for the value of `staticPlacement.locationLinks` in the templates
      {{APP_IMAGE}}         - latest app image
      {{APP_IMAGE_LINK}}    - full link for latest app image, ready to be used for the value of `containers[].image` in the templates
      {{APP_IDENTITY}}      - default identity
      {{APP_IDENTITY_LINK}} - full link for identity, ready to be used for the value of `identityLink` in the templates
      ```
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Applies single template.
      cpl apply-template redis -a $APP_NAME

      # Applies several templates (practically creating full app).
      cpl apply-template app postgres redis rails -a $APP_NAME
      ```
    EX

    def call # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      ensure_templates!

      @created_items = []
      @failed_templates = []
      @skipped_templates = []

      @asked_for_confirmation = false

      pending_templates = templates.select do |template|
        if template == "app"
          confirm_app(template)
        else
          confirm_workload(template)
        end
      end

      progress.puts if @asked_for_confirmation

      @deprecated_variables = []

      pending_templates.each do |template, filename|
        step("Applying template '#{template}'", abort_on_error: false) do
          items = apply_template(filename)
          unless items
            report_failure(template)
            next false
          end

          items.each do |item|
            report_success(item)
          end
          true
        end
      end

      warn_deprecated_variables

      print_created_items
      print_failed_templates
      print_skipped_templates

      exit(ExitCode::ERROR_DEFAULT) if @failed_templates.any?
    end

    private

    def templates
      @templates ||= config.args.to_h do |template|
        [template, "#{config.app_cpln_dir}/templates/#{template}.yml"]
      end
    end

    def ensure_templates!
      missing_templates = templates.reject { |_template, filename| File.exist?(filename) }.to_h
      return if missing_templates.empty?

      missing_templates_str = missing_templates.map do |template, filename|
        "  - #{template} (#{filename})"
      end.join("\n")
      progress.puts("#{Shell.color('Missing templates:', :red)}\n#{missing_templates_str}\n\n")

      raise "Can't find templates above, please create them."
    end

    def confirm_apply(message)
      return true if config.options[:yes]

      @asked_for_confirmation = true
      Shell.confirm(message)
    end

    def confirm_app(template)
      app = cp.fetch_gvc
      return true unless app

      confirmed = confirm_apply("App '#{config.app}' already exists, do you want to re-create it?")
      return true if confirmed

      report_skipped(template)
      false
    end

    def confirm_workload(template)
      workload = cp.fetch_workload(template)
      return true unless workload

      confirmed = confirm_apply("Workload '#{template}' already exists, do you want to re-create it?")
      return true if confirmed

      report_skipped(template)
      false
    end

    def apply_template(filename) # rubocop:disable Metrics/MethodLength
      data = File.read(filename)
                 .gsub("{{APP_ORG}}", config.org)
                 .gsub("{{APP_NAME}}", config.app)
                 .gsub("{{APP_LOCATION}}", config.location)
                 .gsub("{{APP_LOCATION_LINK}}", config.location_link)
                 .gsub("{{APP_IMAGE}}", latest_image)
                 .gsub("{{APP_IMAGE_LINK}}", config.image_link(latest_image))
                 .gsub("{{APP_IDENTITY}}", config.identity)
                 .gsub("{{APP_IDENTITY_LINK}}", config.identity_link)
                 .gsub("{{APP_SECRETS}}", config.secrets)
                 .gsub("{{APP_SECRETS_POLICY}}", config.secrets_policy)

      find_deprecated_variables(data)

      # Kept for backwards compatibility
      data = data
             .gsub("APP_ORG", config.org)
             .gsub("APP_GVC", config.app)
             .gsub("APP_LOCATION", config.location)
             .gsub("APP_IMAGE", latest_image)

      # Don't read in YAML.safe_load as that doesn't handle multiple documents
      cp.apply_template(data)
    end

    def new_variables
      {
        "APP_ORG" => "{{APP_ORG}}",
        "APP_GVC" => "{{APP_NAME}}",
        "APP_LOCATION" => "{{APP_LOCATION}}",
        "APP_IMAGE" => "{{APP_IMAGE}}"
      }
    end

    def find_deprecated_variables(data)
      @deprecated_variables.push(*new_variables.keys.select { |old_key| data.include?(old_key) })
      @deprecated_variables = @deprecated_variables.uniq.sort
    end

    def warn_deprecated_variables
      return unless @deprecated_variables.any?

      message = "Please replace these variables in the templates, " \
                "as support for them will be removed in a future major version bump:"
      deprecated = @deprecated_variables.map { |old_key| "  - #{old_key} -> #{new_variables[old_key]}" }.join("\n")
      progress.puts("\n#{Shell.color("DEPRECATED: #{message}", :yellow)}\n#{deprecated}")
    end

    def report_success(item)
      @created_items.push(item)
    end

    def report_failure(template)
      @failed_templates.push(template)
    end

    def report_skipped(template)
      @skipped_templates.push(template)
    end

    def print_created_items
      return unless @created_items.any?

      created = @created_items.map { |item| "  - [#{item[:kind]}] #{item[:name]}" }.join("\n")
      progress.puts("\n#{Shell.color('Created items:', :green)}\n#{created}")
    end

    def print_failed_templates
      return unless @failed_templates.any?

      failed = @failed_templates.map { |template| "  - #{template}" }.join("\n")
      progress.puts("\n#{Shell.color('Failed to apply templates:', :red)}\n#{failed}")
    end

    def print_skipped_templates
      return unless @skipped_templates.any?

      skipped = @skipped_templates.map { |template| "  - #{template}" }.join("\n")
      progress.puts("\n#{Shell.color('Skipped templates (already exist):', :blue)}\n#{skipped}")
    end
  end
end
