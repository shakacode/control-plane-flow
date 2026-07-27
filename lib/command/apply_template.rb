# frozen_string_literal: true

module Command
  class ApplyTemplate < Base # rubocop:disable Metrics/ClassLength
    NAME = "apply-template"
    USAGE = "apply-template TEMPLATE [TEMPLATE] ... [TEMPLATE]"
    REQUIRES_ARGS = true
    OPTIONS = [
      app_option(required: true),
      location_option,
      skip_confirm_option,
      add_app_identity_option,
      preserve_existing_runtime_option
    ].freeze
    DESCRIPTION = "Applies application-specific configs from templates"
    LONG_DESCRIPTION = <<~DESC
      - Applies application-specific configs from templates (e.g., for every review-app)
      - Publishes (creates or updates) those at Control Plane infrastructure
      - Picks templates from the `.controlplane/templates` directory
      - Templates are ordinary Control Plane templates but with variable preprocessing
      - Use `--preserve-existing-runtime` to retain deployed app images and skip existing secret resources while applying other template changes

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
      {{APP_SECRETS}}       - app secret dictionary name
      {{APP_SECRETS_POLICY}} - app secret policy name
      {{SHARED_SECRET_<NAME>}} - shared secret dictionary name from `shared_secret_grants`
      ```
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Applies single template.
      cpflow apply-template redis -a $APP_NAME

      # Applies several templates (practically creating full app).
      cpflow apply-template app postgres redis rails -a $APP_NAME
      ```
    EX
    VALIDATIONS = %w[config templates].freeze

    def call # rubocop:disable Metrics/MethodLength
      @template_parser = TemplateParser.new(self)
      @names_to_filenames = config.args.to_h do |name|
        [name, @template_parser.template_filename(name)]
      end

      ensure_templates!

      @created_items = []
      @failed_templates = []
      @skipped_templates = []

      templates = @template_parser.parse(@names_to_filenames.values)
      templates = preserve_existing_runtime(templates) if config.options[:preserve_existing_runtime]
      pending_templates = confirm_templates(templates)
      add_app_identity_template(pending_templates) if config.options[:add_app_identity]
      pending_templates.each do |template|
        apply_template(template)
      end

      print_created_items
      print_failed_templates
      print_skipped_templates

      exit(ExitCode::ERROR_DEFAULT) if @failed_templates.any?
    end

    private

    def template_kind(template)
      case template["kind"]
      when "gvc"
        "app"
      else
        template["kind"]
      end
    end

    def ensure_templates!
      missing_templates = @names_to_filenames.reject { |_, filename| File.exist?(filename) }
      return if missing_templates.empty?

      missing_templates_str = missing_templates.map do |name, filename|
        "  - #{name} (#{filename})"
      end.join("\n")
      progress.puts("#{Shell.color('Missing templates:', :red)}\n#{missing_templates_str}\n\n")

      raise "Can't find templates above, please create them."
    end

    # The confirm_* helpers below prompt the user and mutate state (@asked_for_confirmation,
    # report_skipped). `confirm_app` and `confirm_workload` return booleans but have side
    # effects, so their names intentionally lack `?` (suppressed via the inline disables
    # below). `confirm_apply` doesn't trip the cop and needs no annotation.
    def confirm_apply(message)
      return true if config.options[:yes]

      @asked_for_confirmation = true
      Shell.confirm(message)
    end

    def confirm_app(template) # rubocop:disable Naming/PredicateMethod
      app = cp.fetch_gvc(template["name"])
      return true unless app

      confirmed = confirm_apply("App '#{template['name']}' already exists, do you want to re-create it?")
      return true if confirmed

      report_skipped(template)
      false
    end

    def confirm_workload(template) # rubocop:disable Naming/PredicateMethod
      workload = fetch_workload(template["name"])
      return true unless workload

      confirmed = confirm_apply("Workload '#{template['name']}' already exists, do you want to re-create it?")
      return true if confirmed

      report_skipped(template)
      false
    end

    def confirm_templates(templates) # rubocop:disable Metrics/MethodLength
      @asked_for_confirmation = false

      pending_templates = templates.select do |template|
        case template["kind"]
        when "gvc"
          confirm_app(template)
        when "workload"
          confirm_workload(template)
        else
          true
        end
      end

      progress.puts if @asked_for_confirmation

      pending_templates
    end

    def preserve_existing_runtime(templates)
      cache_existing_workloads(templates)
      fallback_image = existing_app_image

      templates.filter_map do |template|
        if template["kind"] == "secret" && cp.fetch_secret(template["name"])
          report_skipped(template)
          next
        end

        preserve_workload_images(template, fallback_image) if template["kind"] == "workload"
        template
      end
    end

    def cache_existing_workloads(templates)
      template_names = templates.filter_map { |template| template["name"] if template["kind"] == "workload" }
      configured_names = configured_app_workload_names
      @existing_workloads = (template_names + configured_names).uniq.to_h do |name|
        [name, cp.fetch_workload(name)]
      end
    end

    def configured_app_workload_names
      Array(config[:app_workloads])
    rescue RuntimeError
      []
    end

    def fetch_workload(name)
      return @existing_workloads[name] if @existing_workloads&.key?(name)

      cp.fetch_workload(name)
    end

    def existing_app_image
      @existing_workloads.values.compact.filter_map do |workload|
        images = Array(workload.dig("spec", "containers")).filter_map { |container| container["image"] }
        images.find { |image| app_image?(image) }
      end.first
    end

    def preserve_workload_images(template, fallback_image) # rubocop:disable Metrics/MethodLength
      existing_containers = Array(fetch_workload(template["name"])&.dig("spec", "containers"))
                            .to_h { |container| [container["name"], container] }

      Array(template.dig("spec", "containers")).each do |container|
        next unless app_image?(container["image"])

        existing_image = existing_containers.dig(container["name"], "image")
        preserved_image = app_image?(existing_image) ? existing_image : fallback_image
        unless preserved_image
          raise "Cannot safely refresh app image for workload '#{template['name']}' without a deployed app image."
        end

        container["image"] = preserved_image
      end
    end

    def app_image?(image)
      image.to_s.match?(
        %r{\A(?:/org/#{Regexp.escape(config.org)}/image/)?#{Regexp.escape(config.app)}[:@]}
      )
    end

    def add_app_identity_template(templates)
      app_template_index = templates.index { |template| template["name"] == config.app }
      app_identity_template_index = templates.index { |template| template["name"] == config.identity }

      return unless app_template_index && app_identity_template_index.nil?

      # Adding the identity template right after the app template is important since:
      # a) we can't create the identity at the beginning because the app doesn't exist yet
      # b) we also can't create it at the end because any workload templates associated with it will fail to apply
      templates.insert(app_template_index + 1, build_app_identity_hash)
    end

    def build_app_identity_hash
      {
        "kind" => "identity",
        "name" => config.identity
      }
    end

    def apply_template(template) # rubocop:disable Metrics/MethodLength
      step("Applying template for #{template_kind(template)} '#{template['name']}'", abort_on_error: false) do
        items = cp.apply_hash(template)
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
