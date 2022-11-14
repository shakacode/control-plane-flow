# frozen_string_literal: true

module Command
  class Build < Base
    def call
      dockerfile = "#{config.app_cpln_dir}/Dockerfile"
      cp.image_build(latest_image_next, dockerfile: dockerfile)
    end
  end
end
