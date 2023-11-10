# frozen_string_literal: true

module Command
  class ApplyTemplate < Base # rubocop:disable Metrics/ClassLength
    NAME = "apply-template"
    USAGE = "apply-template TEMPLATE [TEMPLATE] ... [TEMPLATE]"
    REQUIRES_ARGS = true
    OPTIONS = [
      app_option(required: true),
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
      APP_GVC      - basically GVC or app name
      APP_LOCATION - default location
      APP_ORG      - organization
      APP_IMAGE    - will use latest app image
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

    def call # rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity
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
      if dry_run?
        show_dry_run_message("Confirmed app")
        return true
      end

      app = cp.fetch_gvc
      return true unless app

      confirmed = confirm_apply("App '#{config.app}' already exists, do you want to re-create it?")
      return true if confirmed

      report_skipped(template)
      false
    end

    def confirm_workload(template)
      if dry_run?
        show_dry_run_message("Confirmed workload")
        return true
      end

      workload = cp.fetch_workload(template)
      return true unless workload

      confirmed = confirm_apply("Workload '#{template}' already exists, do you want to re-create it?")
      return true if confirmed

      report_skipped(template)
      false
    end

    def apply_template(filename)
      data = File.read(filename)
                 .gsub("APP_GVC", config.app)
                 .gsub("APP_LOCATION", config[:default_location])
                 .gsub("APP_ORG", config.org)
                 .gsub("APP_IMAGE", latest_image)

      return [{ kind: "DRY_KIND", name: latest_image }] if dry_run?

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
