# frozen_string_literal: true

module Command
  class LatestImage < Base
    def call
      puts latest_image
    end
  end
end
