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
    WITH_INFO_HEADER = false
    VALIDATIONS = [].freeze

    def call
      if config.options[:version]
        run_cpflow_command("version")
      else
        run_cpflow_command("help")
      end
    end
  end
end
