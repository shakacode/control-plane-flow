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

    def call # rubocop:disable Metrics/MethodLength
      ensure_templates!

      @app_status = :existing
      @created_workloads = []
      @failed_workloads = []
      @skipped_workloads = []

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
          apply_template(filename)
          if $CHILD_STATUS.success?
            report_success(template)
          else
            report_failure(template)
          end

          $CHILD_STATUS.success?
        end
      end

      print_app_status
      print_created_workloads
      print_failed_workloads
      print_skipped_workloads
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

    def apply_template(filename)
      data = File.read(filename)
                 .gsub("APP_GVC", config.app)
                 .gsub("APP_LOCATION", config[:default_location])
                 .gsub("APP_ORG", config.org)
                 .gsub("APP_IMAGE", latest_image)

      # Don't read in YAML.safe_load as that doesn't handle multiple documents
      cp.apply_template(data)
    end

    def report_success(template)
      if template == "gvc"
        @app_status = :success
      else
        @created_workloads.push(template)
      end
    end

    def report_failure(template)
      if template == "gvc"
        @app_status = :failure
      else
        @failed_workloads.push(template)
      end
    end

    def report_skipped(template)
      if template == "gvc"
        @app_status = :skipped
      else
        @skipped_workloads.push(template)
      end
    end

    def print_app_status
      return if @app_status == :existing

      case @app_status
      when :success
        progress.puts("\n#{Shell.color("Created app '#{config.app}'.", :green)}")
      when :failure
        progress.puts("\n#{Shell.color("Failed to create app '#{config.app}'.", :red)}")
      when :skipped
        progress.puts("\n#{Shell.color("Skipped app '#{config.app}' (already exists).", :blue)}")
      end
    end

    def print_created_workloads
      return unless @created_workloads.any?

      workloads = @created_workloads.map { |template| "  - #{template}" }.join("\n")
      progress.puts("\n#{Shell.color('Created workloads:', :green)}\n#{workloads}")
    end

    def print_failed_workloads
      return unless @failed_workloads.any?

      workloads = @failed_workloads.map { |template| "  - #{template}" }.join("\n")
      progress.puts("\n#{Shell.color('Failed to create workloads:', :red)}\n#{workloads}")
    end

    def print_skipped_workloads
      return unless @skipped_workloads.any?

      workloads = @skipped_workloads.map { |template| "  - #{template}" }.join("\n")
      progress.puts("\n#{Shell.color('Skipped workloads (already exist):', :blue)}\n#{workloads}")
    end
  end
end
