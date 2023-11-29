# frozen_string_literal: true

class Config # rubocop:disable Metrics/ClassLength
  attr_reader :org_comes_from_env, :app,
              # command line options
              :args, :options

  CONFIG_FILE_LOCATION = ".controlplane/controlplane.yml"

  def initialize(args, options)
    @args = args
    @options = options
    @org_comes_from_env = true if ENV.fetch("CPLN_ORG", nil)
    @app = options[:app]&.strip

    Shell.verbose_mode(options[:verbose])
  end

  def org
    return @org if @org

    @org = options[:org]&.strip

    load_apps
    @org
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

    load_apps
    @current
  end

  private

  def ensure_current_config!
    raise "Can't find current config, please specify an app." unless current
  end

  def ensure_current_config_app!(app_name)
    raise "Can't find app '#{app_name}' in 'controlplane.yml'." unless current
  end

  def ensure_current_config_org!(app_name)
    return if @org

    raise "Can't find option 'cpln_org' for app '#{app_name}' in 'controlplane.yml', " \
          "and CPLN_ORG env var is not set. " \
          "The org can also be provided through --org."
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

  def app_matches_current?(app_name, app_options)
    app && (app_name.to_s == app || (app_options[:match_if_app_name_starts_with] && app.start_with?(app_name.to_s)))
  end

  def pick_current_config(app_name, app_options)
    @current = app_options
    ensure_current_config_app!(app_name)

    return if @org

    @org = current.fetch(:cpln_org)&.strip if current.key?(:cpln_org)
    ensure_current_config_org!(app_name)
  end

  def load_apps # rubocop:disable Metrics/MethodLength
    return if @apps

    @apps = config[:apps].to_h do |app_name, app_options|
      ensure_config_app!(app_name, app_options)

      app_options_with_new_keys = app_options.to_h do |key, value|
        new_key = new_option_keys[key]
        new_key ? [new_key, value] : [key, value]
      end

      if app_matches_current?(app_name, app_options_with_new_keys)
        pick_current_config(app_name, app_options_with_new_keys)
        warn_deprecated_options(app_options)
      end

      [app_name, app_options_with_new_keys]
    end

    ensure_current_config_app!(app) if app
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
