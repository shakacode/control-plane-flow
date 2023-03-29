# frozen_string_literal: true

module Command
  class NoCommand < Base
    NAME = "no-command"
    OPTIONS = [version_option].freeze
    DESCRIPTION = "Called when no command was specified"
    LONG_DESCRIPTION = <<~DESC
      - Called when no command was specified
    DESC
    HIDE = true

    def call
      return unless config.options[:version]

      Version.new(config).call
    end
  end
end
