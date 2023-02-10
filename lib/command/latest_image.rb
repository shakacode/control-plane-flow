# frozen_string_literal: true

module Command
  class LatestImage < Base
    NAME = "latest-image"
    OPTIONS = [
      app_option(required: true)
    ].freeze
    DESCRIPTION = "Displays the latest image name"
    LONG_DESCRIPTION = <<~HEREDOC
      - Displays the latest image name
    HEREDOC

    def call
      puts latest_image
    end
  end
end
