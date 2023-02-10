# frozen_string_literal: true

# Be sure to have run: gem install debug
require "debug"

# rubocop:disable Lint/Debugger
module Command
  class Test < Base
    NAME = "test"
    OPTIONS = all_options
    DESCRIPTION = "For debugging purposes"
    LONG_DESCRIPTION = <<~HEREDOC
      - For debugging purposes
    HEREDOC
    HIDE = true

    def call
      # Change code here to test.
      # You can use `debugger` to debug.
      # debugger
      # Or print values
      pp latest_image_next
    end
  end
end
# rubocop:enable Lint/Debugger
