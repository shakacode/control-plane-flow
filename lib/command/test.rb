# frozen_string_literal: true

require "debug"

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
      # You can use `debugger` to debug.
      # You can use `run_cpflow_command` to simulate a command
      # (e.g., `run_cpflow_command("deploy-image", "-a", "my-app-name")`).
    end
  end
end
