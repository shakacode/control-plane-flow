# frozen_string_literal: true

require "optparse"
require "yaml"
require "pathname"

class Config
  attr_reader :app_dir, :app_config, :app_cp_dir,
              :cmd, :args, :options

  CONFIG_FILE_LOCATIION = ".controlplane/controlplane.yaml"

  def initialize
    load_app_config
    parse_argv
  end

  def review_apps
    app_config.fetch(:review_apps)
  end

  def review_app?
    options[:app].start_with?(review_apps.fetch(:prefix))
  end

  def one_off
    app_config.fetch(:one_off)
  end

  def dockerfile
    "#{app_cp_dir}/Dockerfile"
  end

  def script_path
    Pathname.new(__dir__).parent.parent
  end

  private

  def parse_argv
    @options = {}
    option_parser = OptionParser.new do |opts|
      opts.on "-a", "--app APP"
      opts.on "-w", "--workload WORKLOAD"
    end
    option_parser.parse!(into: options)

    @cmd = ARGV[0].to_sym
    @args = ARGV[1..]
  end

  def load_app_config
    config_file = find_app_config_file
    @app_config = YAML.safe_load_file(config_file, symbolize_names: true)
    @app_cp_dir = File.dirname(config_file)
    @app_dir = Pathname.new(@app_cp_dir).parent.to_s
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
