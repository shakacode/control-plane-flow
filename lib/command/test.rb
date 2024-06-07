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
      # You can use `Cpflow::Cli.start` to simulate a command
      # (e.g., `Cpflow::Cli.start(["deploy-image", "-a", "my-app-name"])`).
    end
  end
end
