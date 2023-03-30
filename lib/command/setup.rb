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

    def call # rubocop:disable Metrics/MethodLength
      @app_status = :existing
      @created_workloads = []
      @failed_workloads = []

      config.args.each do |template|
        filename = "#{config.app_cpln_dir}/templates/#{template}.yml"

        step("Applying template '#{template}'", abort_on_error: false) do
          unless File.exist?(filename)
            report_failure(template)

            raise "Can't find template '#{template}' at '#{filename}', please create it."
          end

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
    end

    private

    def apply_template(filename)
      data = File.read(filename)
                 .gsub("APP_GVC", config.app)
                 .gsub("APP_LOCATION", config[:default_location])
                 .gsub("APP_ORG", config.org)
                 .gsub("APP_IMAGE", latest_image)

      cp.apply(YAML.safe_load(data))
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

    def print_app_status
      return if @app_status == :existing

      if @app_status == :success
        progress.puts("\n#{Shell.color("Created app '#{config.app}'.", :green)}")
      else
        progress.puts("\n#{Shell.color("Failed to create app '#{config.app}'.", :red)}")
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
  end
end
