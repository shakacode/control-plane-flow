# frozen_string_literal: true

module Command
  class Exists < Base
    NAME = "exists"
    OPTIONS = [
      app_option(required: true)
    ].freeze
    DESCRIPTION = "Shell-checks if an application (GVC) exists, useful in scripts"
    LONG_DESCRIPTION = <<~DESC
      - Shell-checks if an application (GVC) exists, useful in scripts, e.g.:
    DESC
    EXAMPLES = <<~EX
      ```sh
      if [ cpl exists -a $APP_NAME ]; ...
      ```
    EX

    def call
      exit(cp.fetch_gvc.nil? ? 64 : 0)
    end
  end
end
