# frozen_string_literal: true

module Command
  class PromoteAppFromUpstream < Base
    NAME = "promote-app-from-upstream"
    OPTIONS = [
      app_option(required: true),
      upstream_token_option(required: true)
    ].freeze
    DESCRIPTION = "Copies the latest image from upstream, runs a release script (optional), and deploys the image"
    LONG_DESCRIPTION = <<~DESC
      - Copies the latest image from upstream, runs a release script (optional), and deploys the image
      - It performs the following steps:
        - Runs `cpl copy-image-from-upstream` to copy the latest image from upstream
        - Runs `cpl deploy-image` to deploy the image
        - If `.controlplane/controlplane.yml` includes the `release_script`, `cpl deploy-image` will use the `--run-release-phase` option
        - The deploy will fail if the release script exits with a non-zero code
    DESC

    def call
      copy_image_from_upstream
      deploy_image
    end

    private

    def copy_image_from_upstream
      Cpl::Cli.start(["copy-image-from-upstream", "-a", config.app, "-t", config.options[:upstream_token]])
      progress.puts
    end

    def deploy_image
      args = []
      args.push("--run-release-phase") if config.current[:release_script]
      Cpl::Cli.start(["deploy-image", "-a", config.app, *args])
    end
  end
end
