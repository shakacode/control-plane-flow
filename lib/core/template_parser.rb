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

    find_deprecated_variables(yaml_file)

    # Kept for backwards compatibility
    yaml_file
      .gsub("APP_ORG", config.org)
      .gsub("APP_GVC", config.app)
      .gsub("APP_LOCATION", config.location)
      .then { |updated_yaml| replace_legacy_image_variable(updated_yaml) }
  end

  def replace_image_variables(yaml_file)
    has_image = yaml_file.include?("{{APP_IMAGE}}")
    has_image_link = yaml_file.include?("{{APP_IMAGE_LINK}}")
    return yaml_file unless has_image || has_image_link

    yaml_file = yaml_file.gsub("{{APP_IMAGE}}", latest_image) if has_image
    yaml_file = yaml_file.gsub("{{APP_IMAGE_LINK}}", config.image_link(latest_image)) if has_image_link
    yaml_file
  end

  def replace_legacy_image_variable(yaml_file)
    return yaml_file unless yaml_file.match?(/\bAPP_IMAGE\b/)

    yaml_file.gsub(/\bAPP_IMAGE\b/, latest_image)
  end

  def latest_image
    @latest_image ||= cp.latest_image
  end

  def find_deprecated_variables(yaml_file)
    new_variables.each do |old_key, new_key|
      @deprecated_variables[old_key] = new_key if yaml_file.include?(old_key)
    end
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
