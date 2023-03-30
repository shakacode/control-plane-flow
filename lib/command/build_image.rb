# frozen_string_literal: true

module Command
  class BuildImage < Base
    NAME = "build-image"
    OPTIONS = [
      app_option(required: true),
      commit_option
    ].freeze
    DESCRIPTION = "Builds and pushes the image to Control Plane"
    LONG_DESCRIPTION = <<~DESC
      - Builds and pushes the image to Control Plane
      - Automatically assigns image numbers, e.g., `app:1`, `app:2`, etc.
      - Uses `.controlplane/Dockerfile`
    DESC

    def call
      ensure_docker_running!

      dockerfile = config.current[:dockerfile] || "Dockerfile"
      dockerfile = "#{config.app_cpln_dir}/#{dockerfile}"
      progress.puts "- Building dockerfile: #{dockerfile}"

      cp.image_build(latest_image_next, dockerfile: dockerfile)
    end

    private

    def ensure_docker_running!
      `docker version > /dev/null 2>&1`
      return if $?.success? # rubocop:disable Style/SpecialGlobalVars

      Shell.abort("Can't run Docker. Please make sure that it's installed and started, then try again.")
    end
  end
end
