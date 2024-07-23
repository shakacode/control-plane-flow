# frozen_string_literal: true

class ValidationError < StandardError; end

class DoctorService
  extend Forwardable

  def_delegators :@command, :config, :progress

  def initialize(command)
    @command = command
  end

  def run_validations(validations, silent_if_passing: false) # rubocop:disable Metrics/MethodLength
    @any_failed_validation = false

    validations.each do |validation|
      case validation
      when "config"
        validate_config
      when "templates"
        validate_templates
      else
        raise ValidationError, Shell.color("ERROR: Invalid validation '#{validation}'.", :red)
      end

      progress.puts("#{Shell.color('[PASS]', :green)} #{validation}") unless silent_if_passing
    rescue ValidationError => e
      @any_failed_validation = true

      progress.puts("#{Shell.color('[FAIL]', :red)} #{validation}\n\n#{e.message}\n\n")
    end

    exit(ExitCode::ERROR_DEFAULT) if @any_failed_validation
  end

  def validate_config
    check_for_app_names_contained_in_others
  end

  def validate_templates
    @template_parser = TemplateParser.new(@command)
    filenames = Dir.glob("#{@template_parser.template_dir}/*.yml")
    templates = @template_parser.parse(filenames)

    check_for_duplicate_templates(templates)
    warn_deprecated_template_variables
  end

  private

  def check_for_app_names_contained_in_others
    app_names_contained_in_others = find_app_names_contained_in_others
    return if app_names_contained_in_others.empty?

    message = "App names contained in others found below. Please ensure that app names are unique."
    list = app_names_contained_in_others
           .map { |app_prefix, app_name| "  - '#{app_prefix}' is a prefix of '#{app_name}'" }
           .join("\n")
    raise ValidationError, "#{Shell.color("ERROR: #{message}", :red)}\n#{list}"
  end

  def find_app_names_contained_in_others # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength
    app_names = config.apps.keys.map(&:to_s).sort
    app_prefixes = config.apps
                         .select { |_, app_options| app_options[:match_if_app_name_starts_with] }
                         .keys
                         .map(&:to_s)
                         .sort
    app_prefixes.each_with_object([]) do |app_prefix, app_names_contained_in_others|
      app_names.each do |app_name|
        if app_prefix != app_name && app_name.start_with?(app_prefix)
          app_names_contained_in_others.push([app_prefix, app_name])
        end
      end
    end
  end

  def check_for_duplicate_templates(templates)
    grouped_templates = templates.group_by { |template| [template["kind"], template["name"]] }
    duplicate_templates = grouped_templates.select { |_, group| group.size > 1 }
    return if duplicate_templates.empty?

    message = "Duplicate templates found with the kind/names below. Please ensure that templates are unique."
    list = duplicate_templates
           .map { |(kind, name), _| "  - kind: #{kind}, name: #{name}" }
           .join("\n")
    raise ValidationError, "#{Shell.color("ERROR: #{message}", :red)}\n#{list}"
  end

  def warn_deprecated_template_variables
    deprecated_variables = @template_parser.deprecated_variables
    return if deprecated_variables.empty?

    message = "Please replace these variables in the templates, " \
              "as support for them will be removed in a future major version bump:"
    list = deprecated_variables
           .map { |old_key, new_key| "  - #{old_key} -> #{new_key}" }
           .join("\n")
    progress.puts("\n#{Shell.color("DEPRECATED: #{message}", :yellow)}\n#{list}\n\n")
  end
end
