# frozen_string_literal: true

class Config
  attr_reader :config, :current,
              :app, :app_dir,
              # command line options
              :cmd, :args, :options

  CONFIG_FILE_LOCATIION = ".controlplane/controlplane.yml"

  def initialize
    load_app_config
    parse_argv
    pick_current_config if app
  end

  def [](key)
    app ? current.fetch(key) : abort("ERROR: should specify app")
  end

  def script_path
    Pathname.new(__dir__).parent.parent
  end

  def app_cpln_dir
    "#{app_dir}/.controlplane"
  end

  private

  def parse_argv # rubocop:disable Metrics/MethodLength
    @options = {}
    option_parser = OptionParser.new do |opts|
      opts.on "-a", "--app APP"
      opts.on "-w", "--workload WORKLOAD"
      opts.on "--image IMAGE"
      opts.on "--altlog"
      opts.on "--commit COMMIT"
    end
    option_parser.parse!(into: options)

    @cmd = ARGV[0].tr(":", "_").to_sym if ARGV[0]
    @args = ARGV[1..]
    @app = options[:app]
  end

  def pick_current_config
    config[:apps].each do |c_app, c_data|
      if c_app.to_s == app || (c_data[:prefix] && app.start_with?(c_app.to_s))
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
