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
  end

  def [](key) # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    abort("ERROR: should specify app") unless app

    logger = $stderr

    if current.key?(key)
      current.fetch(key)
    elsif key == :cpln_org && current.key?(:org)
      logger.puts("DEPRECATED: option 'org' is deprecated, use 'cpln_org' instead\n")
      current.fetch(:org)
    elsif key == :default_location && current.key?(:location)
      logger.puts("DEPRECATED: option 'location' is deprecated, use 'default_location' instead\n")
      current.fetch(:location)
    elsif key == :match_if_app_name_starts_with && current.key?(:prefix)
      logger.puts("DEPRECATED: option 'prefix' is deprecated, use 'match_if_app_name_starts_with' instead\n")
      current.fetch(:prefix)
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
end
