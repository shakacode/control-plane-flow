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
        - Runs a release script if specified through `release_script` in the `.controlplane/controlplane.yml` file
        - Runs `cpl deploy-image` to deploy the image
    DESC

    def call
      check_release_script
      copy_image_from_upstream
      run_release_script
      deploy_image
    end

    private

    def check_release_script
      release_script_name = config.current[:release_script]
      unless release_script_name
        progress.puts("Can't find option 'release_script' for app '#{config.app}' in 'controlplane.yml'. " \
                      "Skipping release script.\n\n")
        return
      end

      @release_script_path = Pathname.new("#{config.app_cpln_dir}/#{release_script_name}").expand_path

      raise "Can't find release script in '#{@release_script_path}'." unless File.exist?(@release_script_path)
    end

    def copy_image_from_upstream
      perform("cpl copy-image-from-upstream -a #{config.app} -t #{config.options[:upstream_token]}")
      progress.puts
    end

    def run_release_script
      return unless @release_script_path

      progress.puts("Running release script...\n\n")
      perform("bash #{@release_script_path}")
      progress.puts
    end

    def deploy_image
      perform("cpl deploy-image -a #{config.app}")
    end
  end
end
