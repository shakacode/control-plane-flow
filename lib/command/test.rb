# frozen_string_literal: true

# Be sure to have run: gem install debug
require "debug"

module Command
  class Test < Base
    def call
      # Change code here to test.
      # You can use `debugger` to debug.
      # debugger
      # Or print values
      pp latest_image_next
    end
  end
end
