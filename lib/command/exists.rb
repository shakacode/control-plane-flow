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
      - Exits 0 when the app exists, 2 when it does not exist, and 64 for other errors.
    DESC
    EXAMPLES = <<~EX
      ```sh
      if cpflow exists -a $APP_NAME; then
        echo "exists"
      elif [ $? -eq 2 ]; then
        echo "not found"
      fi
      ```
    EX

    def call
      exit(cp.fetch_gvc.nil? ? ExitCode::NOT_FOUND : ExitCode::SUCCESS)
    end
  end
end
