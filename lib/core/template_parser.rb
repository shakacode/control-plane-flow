# frozen_string_literal: true

class TemplateParser
  extend Forwardable

  def_delegators :@command, :config, :cp

  attr_reader :deprecated_variables

  def initialize(command)
    @command = command
  end

  def template_dir
    "#{config.app_cpln_dir}/templates"
  end

  def template_filename(name)
    "#{template_dir}/#{name}.yml"
  end

  def parse(filenames)
    @deprecated_variables = {}

    filenames.each_with_object([]) do |filename, templates|
      yaml_file = File.read(filename)
      yaml_file = replace_variables(yaml_file)

      template_yamls = yaml_file.split(/^---\s*$/)
      template_yamls.each do |template_yaml|
        template = YAML.safe_load(template_yaml)
        templates.push(template)
      end
    end
  end

  private

  def replace_variables(yaml_file) # rubocop:disable Metrics/MethodLength
    original_yaml_file = yaml_file
    yaml_file = replace_legacy_variables(yaml_file)

    yaml_file = yaml_file
                .gsub("{{APP_ORG}}", config.org)
                .gsub("{{APP_NAME}}", config.app)
                .gsub("{{APP_LOCATION}}", config.location)
                .gsub("{{APP_LOCATION_LINK}}", config.location_link)
                .gsub("{{APP_IDENTITY}}", config.identity)
                .gsub("{{APP_IDENTITY_LINK}}", config.identity_link)
                .gsub("{{APP_SECRETS}}", config.secrets)
                .gsub("{{APP_SECRETS_POLICY}}", config.secrets_policy)
    yaml_file = replace_image_variables(yaml_file)

    config.shared_secret_placeholders.each do |placeholder, secret_name|
      yaml_file = yaml_file.gsub(placeholder, secret_name)
    end

    find_deprecated_variables(original_yaml_file)
    yaml_file
  end

  def replace_image_variables(yaml_file)
    has_image = yaml_file.include?("{{APP_IMAGE}}")
    has_image_link = yaml_file.include?("{{APP_IMAGE_LINK}}")
    return yaml_file unless has_image || has_image_link

    yaml_file = yaml_file.gsub("{{APP_IMAGE}}", latest_image) if has_image
    yaml_file = yaml_file.gsub("{{APP_IMAGE_LINK}}", config.image_link(latest_image)) if has_image_link
    yaml_file
  end

  # Kept for backwards compatibility.
  def replace_legacy_variables(yaml_file)
    yaml_file
      .gsub(deprecated_variable_pattern("APP_ORG"), config.org)
      .gsub(deprecated_variable_pattern("APP_GVC"), config.app)
      .gsub(deprecated_variable_pattern("APP_LOCATION"), config.location)
      .then { |updated_yaml| replace_legacy_image_variable(updated_yaml) }
  end

  def replace_legacy_image_variable(yaml_file)
    return yaml_file unless deprecated_variable_used?(yaml_file, "APP_IMAGE")

    yaml_file.gsub(deprecated_variable_pattern("APP_IMAGE"), latest_image)
  end

  def latest_image
    # Share one image value across modern and legacy image replacements in this parser instance.
    @latest_image ||= cp.latest_image
  end

  def find_deprecated_variables(yaml_file)
    new_variables.each do |old_key, new_key|
      @deprecated_variables[old_key] = new_key if deprecated_variable_used?(yaml_file, old_key)
    end
  end

  def deprecated_variable_used?(yaml_file, old_key)
    yaml_file.match?(deprecated_variable_pattern(old_key))
  end

  def deprecated_variable_pattern(old_key)
    /(?<!\{\{)\b#{Regexp.escape(old_key)}\b(?!\}\})/
  end

  def new_variables
    {
      "APP_ORG" => "{{APP_ORG}}",
      "APP_GVC" => "{{APP_NAME}}",
      "APP_LOCATION" => "{{APP_LOCATION}}",
      "APP_IMAGE" => "{{APP_IMAGE}}"
    }
  end
end
