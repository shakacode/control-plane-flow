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
      cpl apply-template gvc postgres redis rails -a $APP_NAME
      ```
    EX

    def call # rubocop:disable Metrics/MethodLength
      ensure_templates!

      @deprecated_variables = []
      @created_items = []
      @failed_templates = []
      @skipped_templates = []

      templates = parse_templates
      pending_templates = confirm_templates(templates)
      pending_templates.each do |template|
        apply_template(template)
      end

      warn_deprecated_variables

      print_created_items
      print_failed_templates
      print_skipped_templates

      exit(1) if @failed_templates.any?
    end

    private

    def template_filename(name)
      "#{config.app_cpln_dir}/templates/#{name}.yml"
    end

    def template_kind(template)
      case template["kind"]
      when "gvc" then "app"
      else template["kind"]
      end
    end

    def ensure_templates!
      missing_templates = config.args.reject { |name| File.exist?(template_filename(name)) }
      return if missing_templates.empty?

      missing_templates_str = missing_templates.map do |name|
        "  - #{name} (#{template_filename(name)})"
      end.join("\n")
      progress.puts("#{Shell.color('Missing templates:', :red)}\n#{missing_templates_str}\n\n")

      raise "Can't find templates above, please create them."
    end

    def parse_templates
      config.args.each_with_object([]) do |name, templates|
        data = File.read(template_filename(name))
        data = replace_variables(data)
        templates_data = data.split(/^---\s*$/)
        templates_data.each do |template_data|
          template = YAML.safe_load(template_data)
          templates.push(template)
        end
      end
    end

    def confirm_templates(templates)
      @asked_for_confirmation = false

      pending_templates = templates.select do |template|
        case template["kind"]
        when "gvc" then confirm_app(template)
        when "workload" then confirm_workload(template)
        else true
        end
      end

      progress.puts if @asked_for_confirmation

      pending_templates
    end

    def apply_template(template) # rubocop:disable Metrics/MethodLength
      step("Applying template for #{template_kind(template)} '#{template['name']}'", abort_on_error: false) do
        items = cp.apply_hash(template)
        if items
          items.each do |item|
            report_success(item)
          end
        else
          report_failure(template)
        end

        $CHILD_STATUS.success?
      end
    end

    def confirm_apply(message)
      return true if config.options[:yes]

      @asked_for_confirmation = true
      Shell.confirm(message)
    end

    def confirm_app(template)
      app = cp.fetch_gvc(template["name"])
      return true unless app

      confirmed = confirm_apply("App '#{template['name']}' already exists, do you want to re-create it?")
      return true if confirmed

      report_skipped(template)
      false
    end

    def confirm_workload(template)
      workload = cp.fetch_workload(template["name"])
      return true unless workload

      confirmed = confirm_apply("Workload '#{template['name']}' already exists, do you want to re-create it?")
      return true if confirmed

      report_skipped(template)
      false
    end

    def replace_variables(data) # rubocop:disable Metrics/MethodLength
      data = data
             .gsub("{{APP_ORG}}", config.org)
             .gsub("{{APP_NAME}}", config.app)
             .gsub("{{APP_LOCATION}}", config.location)
             .gsub("{{APP_LOCATION_LINK}}", app_location_link)
             .gsub("{{APP_IMAGE}}", latest_image)
             .gsub("{{APP_IMAGE_LINK}}", app_image_link)
             .gsub("{{APP_IDENTITY}}", app_identity)
             .gsub("{{APP_IDENTITY_LINK}}", app_identity_link)
             .gsub("{{APP_SECRETS}}", app_secrets)
             .gsub("{{APP_SECRETS_POLICY}}", app_secrets_policy)

      find_deprecated_variables(data)

      # Kept for backwards compatibility
      data
        .gsub("APP_ORG", config.org)
        .gsub("APP_GVC", config.app)
        .gsub("APP_LOCATION", config.location)
        .gsub("APP_IMAGE", latest_image)
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

      failed = @failed_templates.map { |template| "  - [#{template_kind(template)}] #{template['name']}" }.join("\n")
      progress.puts("\n#{Shell.color('Failed to apply templates:', :red)}\n#{failed}")
    end

    def print_skipped_templates
      return unless @skipped_templates.any?

      skipped = @skipped_templates.map { |template| "  - [#{template_kind(template)}] #{template['name']}" }.join("\n")
      progress.puts("\n#{Shell.color('Skipped templates (already exist):', :blue)}\n#{skipped}")
    end
  end
end
