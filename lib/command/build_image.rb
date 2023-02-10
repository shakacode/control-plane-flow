# frozen_string_literal: true

module Command
  class BuildImage < Base
    NAME = "build-image"
    OPTIONS = [
      app_option(required: true),
      commit_option
    ].freeze
    DESCRIPTION = "Builds and pushes the image to Control Plane"
    LONG_DESCRIPTION = <<~HEREDOC
      - Builds and pushes the image to Control Plane
      - Automatically assigns image numbers, e.g., `app:1`, `app:2`, etc.
      - Uses `.controlplane/Dockerfile`
    HEREDOC

    def call
      dockerfile = config.current[:dockerfile] || "Dockerfile"
      dockerfile = "#{config.app_cpln_dir}/#{dockerfile}"
      progress.puts "- Building dockerfile: #{dockerfile}"

      cp.image_build(latest_image_next, dockerfile: dockerfile)
    end
  end
end
