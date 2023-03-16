# frozen_string_literal: true

# Be sure to have run: gem install debug
require "debug"

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
      # rubocop:disable Lint/Debugger
      pp latest_image_next
      # rubocop:enable Lint/Debugger
    end
  end
end
