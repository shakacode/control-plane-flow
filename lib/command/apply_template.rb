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
      {{APP_LOCATION}}      - default location
      {{APP_LOCATION_LINK}} - full link for default location, ready to be used in `staticPlacement.locationLinks`
      {{APP_IMAGE}}         - latest app image
      {{APP_IMAGE_LINK}}    - full link for latest app image, ready to be used in `containers[].image`
      {{APP_IDENTITY}}      - default identity
      {{APP_IDENTITY_LINK}} - full link for default identity, ready to be used in `identityLink`
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

    def call # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      ensure_templates!

      @created_items = []
      @failed_templates = []
      @skipped_templates = []

      @asked_for_confirmation = false

      pending_templates = templates.select do |template|
        if template == "gvc"
          confirm_app(template)
        else
          confirm_workload(template)
        end
      end

      progress.puts if @asked_for_confirmation

      pending_templates.each do |template, filename|
        step("Applying template '#{template}'", abort_on_error: false) do
          items = apply_template(filename)
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

      print_created_items
      print_failed_templates
      print_skipped_templates

      exit(1) if @failed_templates.any?
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
                 .gsub("{{APP_LOCATION_LINK}}", app_location_link)
                 .gsub("{{APP_IMAGE}}", latest_image)
                 .gsub("{{APP_IMAGE_LINK}}", app_image_link)
                 .gsub("{{APP_IDENTITY}}", app_identity)
                 .gsub("{{APP_IDENTITY_LINK}}", app_identity_link)
                 .gsub("{{APP_SECRETS}}", app_secrets)
                 .gsub("{{APP_SECRETS_POLICY}}", app_secrets_policy)
                 # Kept for backwards compatibility
                 .gsub("APP_ORG", config.org)
                 .gsub("APP_GVC", config.app)
                 .gsub("APP_LOCATION", config.location)
                 .gsub("APP_IMAGE", latest_image)

      # Don't read in YAML.safe_load as that doesn't handle multiple documents
      cp.apply_template(data)
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
