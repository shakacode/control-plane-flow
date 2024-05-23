# frozen_string_literal: true

module DummyAppSetup
  module_function

  def setup
    config_dir = "#{CommandHelpers.spec_directory}/dummy/.controlplane"

    config_file = File.read("#{config_dir}/controlplane.yml")
    config_file = config_file.gsub("{GLOBAL_IDENTIFIER}", CommandHelpers.dummy_test_app_global_identifier)

    @tmp_config_file = Tempfile.create(["controlplane-tmp-", ".yml"], config_dir)
    @tmp_config_file.write(config_file)
    @tmp_config_file.rewind

    ENV["CONFIG_FILE_PATH"] = @tmp_config_file.path

    puts "\nUsing org '#{CommandHelpers.dummy_test_org}' for tests with dummy app\n\n"
  end

  def cleanup
    if CommandHelpers.apps_to_delete.empty?
      puts "\n\nNo dummy apps to delete\n"
    else
      CommandHelpers.apps_to_delete.each do |app|
        CommandHelpers.run_cpl_command("delete", "-a", app, "--yes")
      end
    end

    File.delete(@tmp_config_file.path) if @tmp_config_file
  end
end
