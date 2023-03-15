# frozen_string_literal: true

class Config
  attr_reader :config, :current,
              :app, :app_dir,
              # command line options
              :args, :options

  CONFIG_FILE_LOCATIION = ".controlplane/controlplane.yml"

  def initialize(args, options)
    @args = args
    @options = options
    @app = options[:app]

    load_app_config
    pick_current_config if app
    warn_deprecated_options if current
  end

  def [](key)
    ensure_current_config

    old_key = old_option_keys[key]
    if current.key?(key)
      current.fetch(key)
    elsif old_key && current.key?(old_key)
      current.fetch(old_key)
    else
      Shell.abort("Can't find option '#{key}' for app '#{app}' in 'controlplane.yml'.")
    end
  end

  def script_path
    Pathname.new(__dir__).parent.parent
  end

  def app_cpln_dir
    "#{app_dir}/.controlplane"
  end

  private

  def ensure_current_config
    Shell.abort("Can't find current config, please specify an app.") unless current
  end

  def ensure_current_config_app(app)
    Shell.abort("Can't find app '#{app}' in 'controlplane.yml'.") unless current
  end

  def ensure_config
    Shell.abort("'controlplane.yml' is empty.") unless config
  end

  def ensure_config_apps
    Shell.abort("Can't find key 'apps' in 'controlplane.yml'.") unless config[:apps]
  end

  def ensure_config_app(app, options)
    Shell.abort("App '#{app}' is empty in 'controlplane.yml'.") unless options
  end

  def pick_current_config
    ensure_config
    ensure_config_apps
    config[:apps].each do |c_app, c_data|
      ensure_config_app(c_app, c_data)
      if c_app.to_s == app || (c_data[:match_if_app_name_starts_with] && app.start_with?(c_app.to_s))
        @current = c_data
        break
      end
    end
    ensure_current_config_app(app)
  end

  def load_app_config
    config_file = find_app_config_file
    @config = YAML.safe_load_file(config_file, symbolize_names: true, aliases: true)
    @app_dir = Pathname.new(config_file).parent.parent.to_s
  end

  def find_app_config_file
    path = Pathname.new(".").expand_path

    loop do
      config_file = path + CONFIG_FILE_LOCATIION
      break config_file if File.file?(config_file)

      path = path.parent

      if path.root?
        Shell.abort("Can't find project config file at 'project_folder/#{CONFIG_FILE_LOCATIION}', please create it.")
      end
    end
  end

  def old_option_keys
    {
      cpln_org: :org,
      default_location: :location,
      match_if_app_name_starts_with: :prefix
    }
  end

  def warn_deprecated_options
    old_option_keys.each do |new_key, old_key|
      if current.key?(old_key)
        Shell.warn_deprecated("Option '#{old_key}' is deprecated, " \
                              "please use '#{new_key}' instead (in 'controlplane.yml').")
      end
    end
  end
end
