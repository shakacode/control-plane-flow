# frozen_string_literal: true

module Command
  class Test < Base
    NAME = "test"
    OPTIONS = all_options
    DESCRIPTION = "For debugging purposes"
    LONG_DESCRIPTION = <<~DESC
      - For debugging purposes
    DESC
    HIDE = true
    VALIDATIONS = [].freeze

    def call
      # Modify this method to trigger the code you want to test.
      # Add `require "debug"` locally if you want to use `debugger`.
      # You can use `run_cpflow_command` to simulate a command
      # (e.g., `run_cpflow_command("deploy-image", "-a", "my-app-name")`).
    end
  end
end
