# frozen_string_literal: true

module Command
  class Exist < Base
    NAME = "exist"
    OPTIONS = [
      app_option(required: true)
    ].freeze
    DESCRIPTION = "Shell-checks if an application (GVC) exists, useful in scripts"
    LONG_DESCRIPTION = <<~HEREDOC
      - Shell-checks if an application (GVC) exists, useful in scripts, e.g.:
    HEREDOC
    EXAMPLES = <<~HEREDOC
      ```sh
      if [ cpl exist -a $APP_NAME ]; ...
      ```
    HEREDOC

    def call
      exit(!cp.gvc_get.nil?)
    end
  end
end
