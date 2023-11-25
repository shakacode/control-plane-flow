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
    return @org if @org

    load_org
    @org
  end

  def app
    return @app if @app

    load_app
    @app
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
    @config || begin
      @config = YAML.safe_load_file(config_file_path, symbolize_names: true, aliases: true)
      ensure_config!
      ensure_config_apps!
      @config
    end
  end

  def apps
    return @apps if @apps

    load_apps
    @apps
  end

  def current
    return @current if @current

    load_app
    @current
  end

  private

  def ensure_current_config!
    raise "Can't find current config, please specify an app." unless current
  end

  def ensure_current_config_app!
    raise "Can't find app '#{app}' in 'controlplane.yml'." unless current
  end

  def ensure_config!
    raise "'controlplane.yml' is empty." unless config
  end

  def ensure_config_apps!
    raise "Can't find key 'apps' in 'controlplane.yml'." unless config[:apps]
  end

  def ensure_config_app!(app_name, app_options)
    raise "App '#{app_name}' is empty in 'controlplane.yml'." unless app_options
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

  def pick_current_config(app_name, app_options)
    @app = app_name
    @current = app_options
    ensure_current_config_app!

    warn_deprecated_options(app_options)
  end

  def load_apps
    return if @apps

    @apps = config[:apps].to_h do |app_name, app_options|
      ensure_config_app!(app_name, app_options)

      app_options_with_new_keys = app_options.to_h do |key, value|
        new_key = new_option_keys[key]
        new_key ? [new_key, value] : [key, value]
      end

      [app_name, app_options_with_new_keys]
    end
  end

  def config_file_path
    return @config_file_path if @config_file_path

    path = Pathname.new(".").expand_path

    @config_file_path = loop do
      config_file = path + CONFIG_FILE_LOCATION
      break config_file if File.file?(config_file)

      path = path.parent

      if path.root?
        raise "Can't find project config file at 'project_folder/#{CONFIG_FILE_LOCATION}', please create it."
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

    pick_current_config(app_from_env, app_config)
    @app_comes_from_env = true
  end

  def load_app
    return if @app

    load_app_from_env
    return if @app

    app_from_options = strip_str_and_validate(options[:app])
    return unless app_from_options

    app_config = find_app_config(app_from_options)
    ensure_config_app!(app_from_options, app_config)

    pick_current_config(app_from_options, app_config)
  end

  def load_org_from_env
    org_from_env = strip_str_and_validate(ENV.fetch("CPLN_ORG", nil))
    return unless org_from_env

    key_exists = current&.key?(:allow_org_override_by_env)
    allowed_locally = key_exists && current[:allow_org_override_by_env]
    allowed_globally = !key_exists && config[:allow_org_override_by_env]
    return unless allowed_locally || allowed_globally

    @org = org_from_env
    @org_comes_from_env = true
  end

  def load_org
    return if @org

    load_org_from_env
    return if @org

    org_from_options = strip_str_and_validate(options[:org])
    @org = org_from_options if org_from_options
    return if @org || !current

    @org = strip_str_and_validate(current[:cpln_org]) if current.key?(:cpln_org)
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
