# frozen_string_literal: true

module Command
  class PromoteAppFromUpstream < Base
    NAME = "promote-app-from-upstream"
    OPTIONS = [
      app_option(required: true),
      upstream_token_option(required: true),
      use_digest_image_ref_option
    ].freeze
    DESCRIPTION = "Copies the latest image from upstream, runs a release script (optional), and deploys the image"
    LONG_DESCRIPTION = <<~DESC
      - Copies the latest image from upstream, runs a release script (optional), and deploys the image
      - It performs the following steps:
        - Runs `cpflow copy-image-from-upstream` to copy the latest image from upstream
        - Runs `cpflow deploy-image` to deploy the image
        - If `.controlplane/controlplane.yml` includes the `release_script`, `cpflow deploy-image` will use the `--run-release-phase` option
        - If the release script exits with a non-zero code, the command will stop executing and also exit with a non-zero code
        - If `use_digest_image_ref` is `true` in the `.controlplane/controlplane.yml` file or `--use-digest-image-ref` option is provided, deployed image's reference will include its digest
    DESC

    def call
      copy_image_from_upstream
      deploy_image
    end

    private

    def copy_image_from_upstream
      run_cpflow_command("copy-image-from-upstream", "-a", config.app, "-t", config.options[:upstream_token])
      progress.puts
    end

    def deploy_image
      args = []
      args.push("--run-release-phase") if config.current&.dig(:release_script)
      digest_image_ref_option = deploy_image_digest_ref_option
      args.push(digest_image_ref_option) if digest_image_ref_option
      run_cpflow_command("deploy-image", "-a", config.app, *args)
    end

    def deploy_image_digest_ref_option
      # Forward explicit false so a parent CLI override is not lost when the child command re-reads YAML.
      return "--no-use-digest-image-ref" if config.options[:use_digest_image_ref] == false

      "--use-digest-image-ref" if config.use_digest_image_ref?
    end
  end
end
