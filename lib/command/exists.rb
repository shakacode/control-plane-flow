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
      - Exits 0 when the app exists, 3 when it does not exist, and 64 for other errors.
    DESC
    EXAMPLES = <<~EX
      ```sh
      cpflow exists -a "$APP_NAME"
      status=$?
      if [ "$status" -eq 0 ]; then
        echo "exists"
      elif [ "$status" -eq 3 ]; then
        echo "not found"
      else
        echo "error: cpflow exists exited $status"
      fi
      ```
    EX

    def call
      exit(cp.fetch_gvc.nil? ? ExitCode::NOT_FOUND : ExitCode::SUCCESS)
    rescue StandardError => e
      Shell.abort(e.message)
    end
  end
end
