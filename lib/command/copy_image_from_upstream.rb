# frozen_string_literal: true

module Command
  class CopyImageFromUpstream < Base
    NAME = "copy-image-from-upstream"
    OPTIONS = [
      app_option(required: true),
      upstream_token_option,
      image_option
    ].freeze
    DESCRIPTION = "Copies an image (by default the latest) from a source org to the current org"
    LONG_DESCRIPTION = <<~DESC
      - Copies an image (by default the latest) from a source org to the current org
      - The source app must be specified either through the `CPLN_UPSTREAM` env var or `upstream` in the `.controlplane/controlplane.yml` file
      - The token for the source org must be provided through `--upstream-token`/`-t` or the `CPLN_UPSTREAM_TOKEN` env var
      - A `cpln` profile will be temporarily created to pull the image from the source org
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Copies the latest image from the source org to the current org.
      cpflow copy-image-from-upstream -a $APP_NAME --upstream-token $UPSTREAM_TOKEN

      # Equivalent call using an env var (avoids exposing the token via the OS process table).
      CPLN_UPSTREAM_TOKEN=$UPSTREAM_TOKEN cpflow copy-image-from-upstream -a $APP_NAME

      # Copies a specific image from the source org to the current org.
      cpflow copy-image-from-upstream -a $APP_NAME --upstream-token $UPSTREAM_TOKEN --image appimage:123
      ```
    EX

    def call # rubocop:disable Metrics/MethodLength
      ensure_docker_running!

      @upstream = ENV.fetch("CPLN_UPSTREAM", nil) || config[:upstream]
      @upstream_org = ENV.fetch("CPLN_ORG_UPSTREAM", nil) || config.find_app_config(@upstream)&.dig(:cpln_org)
      @upstream_token = config.options[:upstream_token] || ENV.fetch("CPLN_UPSTREAM_TOKEN", nil)
      ensure_upstream_org!
      ensure_upstream_token!

      create_upstream_profile
      fetch_upstream_image_url
      fetch_app_image_url
      pull_image_from_upstream
      push_image_to_app
    ensure
      cp.profile_switch("default")
      delete_upstream_profile
    end

    private

    def ensure_upstream_org!
      return if @upstream_org

      raise "Can't find option 'cpln_org' for app '#{@upstream}' in 'controlplane.yml', " \
            "and CPLN_ORG_UPSTREAM env var is not set."
    end

    def ensure_upstream_token!
      return if @upstream_token && !@upstream_token.strip.empty?

      raise "Missing upstream token. Pass `--upstream-token`/`-t` or set the `CPLN_UPSTREAM_TOKEN` env var."
    end

    def create_upstream_profile
      step("Creating upstream profile") do
        loop do
          @upstream_profile = "upstream-#{random_four_digits}"
          break unless cp.profile_exists?(@upstream_profile)
        end

        cp.profile_create(@upstream_profile, @upstream_token)
      end
    end

    def fetch_upstream_image_url
      step("Fetching upstream image URL") do
        cp.profile_switch(@upstream_profile)
        upstream_image = config.options[:image]
        upstream_image = cp.latest_image(@upstream, @upstream_org) if !upstream_image || upstream_image == "latest"
        @commit = cp.extract_image_commit(upstream_image)
        @upstream_image_url = "#{@upstream_org}.registry.cpln.io/#{upstream_image}"
      rescue ControlplaneApiDirect::ForbiddenError => e
        Shell.write_to_tmp_stderr(e.message)
        false
      end
    end

    def fetch_app_image_url
      step("Fetching app image URL") do
        cp.profile_switch("default")
        app_image = cp.latest_image_next(config.app, config.org, commit: @commit)
        @app_image_url = "#{config.org}.registry.cpln.io/#{app_image}"
      end
    end

    def pull_image_from_upstream
      step("Pulling image from '#{@upstream_image_url}'") do
        cp.profile_switch(@upstream_profile)
        cp.image_login(@upstream_org)
        cp.image_pull(@upstream_image_url)
      end
    end

    def push_image_to_app
      step("Pushing image to '#{@app_image_url}'") do
        cp.profile_switch("default")
        cp.image_login(config.org)
        cp.image_tag(@upstream_image_url, @app_image_url)
        cp.image_push(@app_image_url)
      end
    end

    def delete_upstream_profile
      return unless @upstream_profile

      step("Deleting upstream profile") do
        cp.profile_delete(@upstream_profile)
      end
    end
  end
end
