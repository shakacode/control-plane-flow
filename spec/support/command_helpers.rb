# frozen_string_literal: true

require "securerandom"
require "pty"

require_relative "spawned_command"

module CommandHelpers # rubocop:disable Metrics/ModuleLength
  module_function

  DUMMY_TEST_ORG = ENV.fetch("CPLN_ORG")
  DUMMY_TEST_APP_PREFIX = "dummy-test"

  CREATE_APP_PARAMS = {
    "default" => {
      deploy: false,
      image_before_deploy_count: 0,
      image_after_deploy_count: 0
    },
    "full" => {
      deploy: true,
      image_before_deploy_count: 2,
      image_after_deploy_count: 0
    },
    "image-retention" => {
      deploy: false,
      image_before_deploy_count: 3,
      image_after_deploy_count: 0
    },
    "rails-non-app-image" => {
      deploy: false,
      image_before_deploy_count: 1,
      image_after_deploy_count: 0
    },
    "rails-env" => {
      deploy: true,
      image_before_deploy_count: 1,
      image_after_deploy_count: 0
    }
  }.freeze

  def config_dir
    "#{spec_directory}/dummy/.controlplane"
  end

  def config_file_prefix(extra_prefix = "")
    prefix = "controlplane"
    prefix += "-#{extra_prefix}" unless extra_prefix.nil? || extra_prefix.empty?

    prefix
  end

  def configure_config_file(extra_prefix = "")
    prefix = config_file_prefix(extra_prefix)

    config_file = File.read("#{config_dir}/#{prefix}.yml")
    config_file = config_file.gsub("{GLOBAL_IDENTIFIER}", dummy_test_app_global_identifier)

    @@tmp_config_file = Tempfile.create(["#{prefix}-tmp-", ".yml"], config_dir) # rubocop:disable Style/ClassVars
    @@tmp_config_file.write(config_file)
    @@tmp_config_file.rewind

    ENV["CONFIG_FILE_PATH"] = @@tmp_config_file.path
  end

  def delete_config_file
    return unless @@tmp_config_file

    File.delete(@@tmp_config_file.path)

    @@tmp_config_file = nil # rubocop:disable Style/ClassVars
    ENV["CONFIG_FILE_PATH"] = nil
  end

  def temporarily_switch_config_file(extra_prefix = "")
    @@tmp_config_file_bkp = @@tmp_config_file # rubocop:disable Style/ClassVars

    configure_config_file(extra_prefix)
  end

  def restore_config_file
    delete_config_file
    return unless @@tmp_config_file_bkp

    @@tmp_config_file = @@tmp_config_file_bkp # rubocop:disable Style/ClassVars
    ENV["CONFIG_FILE_PATH"] = @@tmp_config_file.path
  end

  def dummy_test_org
    DUMMY_TEST_ORG
  end

  def dummy_test_app_global_identifier
    @@global_identifier ||= SecureRandom.hex(2) # rubocop:disable Style/ClassVars
  end

  # `extra_prefix` is used to differentiate between different dummy apps,
  # e.g., "dummy-test-default", "dummy-test-with-nothing", etc.
  #
  # Returns the full prefix.
  def dummy_test_app_prefix(extra_prefix = "")
    prefix = DUMMY_TEST_APP_PREFIX
    prefix += "-#{extra_prefix}" unless extra_prefix.nil? || extra_prefix.empty?
    prefix += "-#{dummy_test_app_global_identifier}"

    prefix
  end

  # `extra_prefix` is used to differentiate between different dummy apps,
  # e.g., "dummy-test-default", "dummy-test-with-nothing", etc.
  #
  # `suffix` is used to differentiate between different dummy apps with the same `extra_prefix`,
  # e.g., "dummy-test-default-1", "dummy-test-default-2", etc.
  # If `suffix` is `nil` or empty, a random suffix is generated.
  #
  # If `create_if_not_exists` is `true`, the app is created if it doesn't exist,
  # using the definition from `.controlplane/controlplane.yml` for the `extra_prefix`,
  # and the corresponding params from `CREATE_APP_PARAMS`.
  # No random suffix is generated in this case, since the app name must remain the same across multiple specs.
  #
  # Returns the app name.
  def dummy_test_app(extra_prefix = "", suffix = "", create_if_not_exists: false) # rubocop:disable Metrics/CyclomaticComplexity
    prefix = dummy_test_app_prefix(extra_prefix)
    suffix = SecureRandom.hex(2) if (suffix.nil? || suffix.empty?) && !create_if_not_exists

    app = prefix
    app += "-#{suffix}" unless suffix.nil? || suffix.empty?
    return app unless create_if_not_exists

    params = CREATE_APP_PARAMS[extra_prefix] || CREATE_APP_PARAMS["default"]
    create_app_if_not_exists(app, **params)

    app
  end

  def apps_to_delete
    @@apps_to_delete ||= [] # rubocop:disable Style/ClassVars
  end

  def create_app_if_not_exists(app, deploy: false, image_before_deploy_count: 0, image_after_deploy_count: 0) # rubocop:disable Metrics/MethodLength
    apps_to_delete.push(app) unless apps_to_delete.include?(app)

    result = run_cpflow_command("exists", "-a", app)
    return app if result[:status].zero?

    puts "\nCreating app '#{app}' for tests\n\n" if ENV.fetch("VERBOSE_TESTS", nil) == "true"

    run_cpflow_command!("setup-app", "-a", app, "--skip-secrets-setup")

    image_before_deploy_count.times do
      run_cpflow_command!("build-image", "-a", app)
    end
    run_cpflow_command!("deploy-image", "-a", app) if deploy
    image_after_deploy_count.times do
      run_cpflow_command!("build-image", "-a", app)
    end

    app
  end

  def run_cpflow_command(*args, raise_errors: false) # rubocop:disable Metrics/MethodLength
    LogHelpers.write_command_to_log(args.join(" "))

    result = {
      status: 0,
      stderr: "",
      stdout: ""
    }

    original_stderr = replace_stderr
    original_stdout = replace_stdout

    begin
      Cpflow::Cli.start(args)
    rescue SystemExit => e
      result[:status] = e.status
    end

    result[:stderr] = restore_stderr(original_stderr)
    result[:stdout] = restore_stdout(original_stdout)

    LogHelpers.write_command_result_to_log(result)

    raise result.to_json if result[:status].nonzero? && raise_errors

    result
  end

  def run_cpflow_command!(*args)
    run_cpflow_command(*args, raise_errors: true)
  end

  def spawn_cpflow_command(*args, stty_rows: nil, stty_cols: nil, wait_for_process: true)
    cmd = ""
    cmd += "stty rows #{stty_rows} && " if stty_rows
    cmd += "stty cols #{stty_cols} && " if stty_cols
    cmd += "#{cpflow_executable_with_simplecov} #{args.join(' ')}"

    LogHelpers.write_command_to_log(cmd)

    PTY.spawn(cmd) do |output, input, pid|
      yield(SpawnedCommand.new(output, input, pid))
    ensure
      Process.wait(pid) if wait_for_process
    end
  end

  def replace_stderr
    original_stderr = $stderr
    $stderr = Tempfile.create

    original_stderr
  end

  def replace_stdout
    original_stdout = $stdout
    $stdout = Tempfile.create

    original_stdout
  end

  def restore_stderr(original_stderr)
    $stderr.rewind
    contents = $stderr.read
    $stderr.close
    $stderr = original_stderr

    contents
  end

  def restore_stdout(original_stdout)
    $stdout.rewind
    contents = $stdout.read
    $stdout.close
    $stdout = original_stdout

    contents
  end

  def cpflow_executable
    File.join(root_directory, "cpflow")
  end

  def cpflow_executable_with_simplecov
    "ruby -r #{simplecov_spawn_file} #{cpflow_executable}"
  end

  def simplecov_spawn_file
    File.join(root_directory, ".simplecov_spawn")
  end

  def root_directory
    File.dirname(spec_directory)
  end

  def spec_directory
    current_file_path = File.expand_path(__FILE__)
    current_directory = File.dirname(current_file_path)

    File.dirname(current_directory)
  end
end
