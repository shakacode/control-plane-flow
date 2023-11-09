# frozen_string_literal: true

module Command
  class LatestImage < Base
    NAME = "latest-image"
    OPTIONS = [
      app_option(required: true)
    ].freeze
    DESCRIPTION = "Displays the latest image name"
    LONG_DESCRIPTION = <<~DESC
      - Displays the latest image name
    DESC
    WITH_INFO_HEADER = false

    def call
      puts latest_image
    end
  end
end
