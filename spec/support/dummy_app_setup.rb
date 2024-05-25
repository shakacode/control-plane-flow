# frozen_string_literal: true

module DummyAppSetup
  module_function

  def setup
    CommandHelpers.configure_config_file

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

    CommandHelpers.delete_config_file
  end
end
