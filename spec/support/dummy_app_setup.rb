# frozen_string_literal: true

require_relative "stale_dummy_app_sweeper"

module DummyAppSetup
  module_function

  def setup
    CommandHelpers.configure_config_file

    puts "\nUsing org '#{CommandHelpers.dummy_test_org}' for tests with dummy app\n\n"

    # Reclaim quota leaked by earlier runs that were killed before `cleanup`
    # could run. `SKIP_CLEANUP` is this suite's "delete nothing" switch, so it
    # covers the sweep too.
    StaleDummyAppSweeper.sweep unless skip_cleanup?
  end

  def cleanup
    if CommandHelpers.apps_to_delete.empty?
      puts "\n\nNo dummy apps to delete\n"
    else
      CommandHelpers.apps_to_delete.each do |app|
        CommandHelpers.run_cpflow_command("delete", "-a", app, "--yes")
      end
    end

    CommandHelpers.delete_config_file
  end

  def skip_cleanup?
    ENV.fetch("SKIP_CLEANUP", nil) == "true"
  end
end
