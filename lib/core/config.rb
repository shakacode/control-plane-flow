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
    abort("ERROR: should specify app") unless app

    old_key = old_option_keys[key]
    if current.key?(key)
      current.fetch(key)
    elsif old_key && current.key?(old_key)
      current.fetch(old_key)
    else
      abort("ERROR: should specify #{key} in controlplane.yml")
    end
  end

  def script_path
    Pathname.new(__dir__).parent.parent
  end

  def app_cpln_dir
    "#{app_dir}/.controlplane"
  end

  private

  def pick_current_config
    config[:apps].each do |c_app, c_data|
      if c_app.to_s == app || (c_data[:match_if_app_name_starts_with] && app.start_with?(c_app.to_s))
        @current = c_data
        break
      end
    end
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
        puts "ERROR: Can't find project config file, should be 'project_folder/#{CONFIG_FILE_LOCATIION}'"
        exit(-1)
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
