# frozen_string_literal: true

module Command
  class Version < Base
    NAME = "version"
    DESCRIPTION = "Displays the current version of the CLI"
    LONG_DESCRIPTION = <<~DESC
      - Displays the current version of the CLI
      - Can also be done with `cpl --version` or `cpl -v`
    DESC
    WITH_INFO_HEADER = false

    def call
      puts Cpl::VERSION
    end
  end
end
