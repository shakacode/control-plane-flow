# frozen_string_literal: true

module Command
  class Version < Base
    NAME = "version"
    DESCRIPTION = "Displays the current version of the CLI"
    LONG_DESCRIPTION = <<~DESC
      - Displays the current version of the CLI
      - Can also be done with `cpflow --version` or `cpflow -v`
    DESC
    WITH_INFO_HEADER = false
    VALIDATIONS = [].freeze

    def call
      puts Cpflow::VERSION
    end
  end
end
