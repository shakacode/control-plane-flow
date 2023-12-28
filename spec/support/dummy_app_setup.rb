# frozen_string_literal: true

module DummyAppSetup
  module_function

  def setup
    ENV["CONFIG_FILE_PATH"] = "#{CommandHelpers.spec_directory}/dummy/.controlplane/controlplane.yml"

    puts "\nUsing org '#{CommandHelpers.dummy_test_org}' for tests with dummy app\n\n"
  end

  def cleanup
    if CommandHelpers.apps_to_delete.empty?
      puts "\nNo dummy apps to delete\n\n"
      return
    end

    CommandHelpers.apps_to_delete.each do |app|
      CommandHelpers.run_cpl_command("delete", "-a", app, "--yes")
    end
  end
end
