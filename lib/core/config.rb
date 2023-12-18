# frozen_string_literal: true

require_relative "helpers"

class Config # rubocop:disable Metrics/ClassLength
  attr_reader :org_comes_from_env, :app_comes_from_env,
              # command line options
              :args, :options, :required_options

  include Helpers

  CONFIG_FILE_LOCATION = ".controlplane/controlplane.yml"

  def initialize(args, options, required_options)
    @args = args
    @options = options
    @required_options = required_options

    ensure_required_options!

    Shell.verbose_mode(options[:verbose])
  end

  def org
    @org ||= load_org_from_options || load_org_from_env || load_org_from_file
  end

  def app
    @app ||= load_app_from_options || load_app_from_env
  end

  def location
    @location ||= load_location_from_options || load_location_from_env
  end

  def [](key)
    ensure_current_config!

    raise "Can't find option '#{key}' for app '#{app}' in 'controlplane.yml'." unless current.key?(key)

    current.fetch(key)
  end

  def script_path
    Pathname.new(__dir__).parent.parent
  end

  def app_cpln_dir
    "#{app_dir}/.controlplane"
  end

  def should_app_start_with?(app_name)
    apps[app_name.to_sym]&.dig(:match_if_app_name_starts_with) || false
  end

  def app_dir
    Pathname.new(config_file_path).parent.parent.to_s
  end

  def config
    @config ||= begin
      global_config = YAML.safe_load_file(config_file_path, symbolize_names: true, aliases: true)
      ensure_config!(global_config)
      ensure_config_apps!(global_config)

      global_config
    end
  end

  def apps
    @apps ||= config[:apps].to_h do |app_name, app_options|
      ensure_config_app!(app_name, app_options)

      app_options_with_new_keys = app_options.to_h do |key, value|
        new_key = new_option_keys[key]
        new_key ? [new_key, value] : [key, value]
      end

      [app_name, app_options_with_new_keys]
    end
  end

  def current
    return unless app

    @current ||= begin
      app_config = find_app_config(app)
      ensure_config_app!(app, app_config)

      warn_deprecated_options(app_config)

      app_config
    end
  end

  private

  def ensure_current_config!
    raise "Can't find current config, please specify an app." unless current
  end

  def ensure_config!(global_config)
    raise "'controlplane.yml' is empty." unless global_config
  end

  def ensure_config_apps!(global_config)
    raise "Can't find key 'apps' in 'controlplane.yml'." unless global_config[:apps]
  end

  def ensure_config_app!(app_name, app_options)
    raise "Can't find config for app '#{app_name}' in 'controlplane.yml'." unless app_options
  end

  def app_matches?(app_name1, app_name2, app_options)
    app_name1 && app_name2 &&
      (app_name1.to_s == app_name2.to_s ||
        (app_options[:match_if_app_name_starts_with] && app_name1.to_s.start_with?(app_name2.to_s))
      )
  end

  def find_app_config(app_name1)
    @app_configs ||= {}
    @app_configs[app_name1] ||= apps.find do |app_name2, app_config|
                                  app_matches?(app_name1, app_name2, app_config)
                                end&.last
  end

  def ensure_app!
    return if app

    raise "No app provided. " \
          "The app can be provided either through the CPLN_APP env var " \
          "('allow_app_override_by_env' must be set to true in 'controlplane.yml'), " \
          "or the --app command option."
  end

  def ensure_org!
    return if org

    raise "No org provided. " \
          "The org can be provided either through the CPLN_ORG env var " \
          "('allow_org_override_by_env' must be set to true in 'controlplane.yml'), " \
          "the --org command option, " \
          "or the 'cpln_org' key in 'controlplane.yml'."
  end

  def ensure_required_options! # rubocop:disable Metrics/CyclomaticComplexity
    ensure_app! if required_options.include?(:app)
    ensure_org! if required_options.include?(:org) || app

    missing_str = required_options
                  .reject { |option_name| %i[org app].include?(option_name) || options.key?(option_name) }
                  .map { |option_name| "--#{option_name}" }
                  .join(", ")

    raise "Required options missing: #{missing_str}" unless missing_str.empty?
  end

  def config_file_path # rubocop:disable Metrics/MethodLength
    @config_file_path ||= begin
      path = Pathname.new(".").expand_path

      loop do
        config_file = path + CONFIG_FILE_LOCATION
        break config_file if File.file?(config_file)

        path = path.parent

        if path.root?
          raise "Can't find project config file at 'project_folder/#{CONFIG_FILE_LOCATION}', please create it."
        end
      end
    end
  end

  def new_option_keys
    {
      org: :cpln_org,
      location: :default_location,
      prefix: :match_if_app_name_starts_with,
      setup: :setup_app_templates,
      old_image_retention_days: :image_retention_days
    }
  end

  def load_app_from_env
    app_from_env = strip_str_and_validate(ENV.fetch("CPLN_APP", nil))
    return unless app_from_env

    app_config = find_app_config(app_from_env)
    ensure_config_app!(app_from_env, app_config)

    key_exists = app_config.key?(:allow_app_override_by_env)
    allowed_locally = key_exists && app_config[:allow_app_override_by_env]
    allowed_globally = !key_exists && config[:allow_app_override_by_env]
    return unless allowed_locally || allowed_globally

    @app_comes_from_env = true

    app_from_env
  end

  def load_app_from_options
    app_from_options = strip_str_and_validate(options[:app])
    return unless app_from_options

    app_config = find_app_config(app_from_options)
    ensure_config_app!(app_from_options, app_config)

    app_from_options
  end

  def load_org_from_env
    org_from_env = strip_str_and_validate(ENV.fetch("CPLN_ORG", nil))
    return unless org_from_env

    key_exists = current&.key?(:allow_org_override_by_env)
    allowed_locally = key_exists && current[:allow_org_override_by_env]
    allowed_globally = !key_exists && config[:allow_org_override_by_env]
    return unless allowed_locally || allowed_globally

    @org_comes_from_env = true

    org_from_env
  end

  def load_org_from_options
    strip_str_and_validate(options[:org])
  end

  def load_org_from_file
    return unless current&.key?(:cpln_org)

    strip_str_and_validate(current[:cpln_org])
  end

  def load_location_from_options
    strip_str_and_validate(options[:location])
  end

  def load_location_from_env
    strip_str_and_validate(ENV.fetch("CPLN_LOCATION", nil))
  end

  def load_location_from_file
    return unless current&.key?(:default_location)

    strip_str_and_validate(options[:default_location])
  end

  def warn_deprecated_options(app_options)
    deprecated_option_keys = new_option_keys.select { |old_key| app_options.key?(old_key) }
    return if deprecated_option_keys.empty?

    deprecated_option_keys.each do |old_key, new_key|
      Shell.warn_deprecated("Option '#{old_key}' is deprecated, " \
                            "please use '#{new_key}' instead (in 'controlplane.yml').")
    end
    $stderr.puts
  end
end
