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
                .gsub("{{APP_IMAGE}}", cp.latest_image)
                .gsub("{{APP_IMAGE_LINK}}", config.image_link(cp.latest_image))
                .gsub("{{APP_IDENTITY}}", config.identity)
                .gsub("{{APP_IDENTITY_LINK}}", config.identity_link)
                .gsub("{{APP_SECRETS}}", config.secrets)
                .gsub("{{APP_SECRETS_POLICY}}", config.secrets_policy)

    find_deprecated_variables(yaml_file)

    # Kept for backwards compatibility
    yaml_file
      .gsub("APP_ORG", config.org)
      .gsub("APP_GVC", config.app)
      .gsub("APP_LOCATION", config.location)
      .gsub("APP_IMAGE", cp.latest_image)
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
