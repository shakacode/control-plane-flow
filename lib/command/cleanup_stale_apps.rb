# frozen_string_literal: true

module Command
  class CleanupStaleApps < Base # rubocop:disable Metrics/ClassLength
    CLEANUP_MODE_OPTION = {
      name: :mode,
      params: {
        banner: "MODE",
        desc: "Action to take on stale apps: `delete` (default) or `stop`",
        type: :string,
        required: false,
        default: "delete",
        valid_regex: /^(delete|stop)$/
      }
    }.freeze

    NAME = "cleanup-stale-apps"
    OPTIONS = [
      app_option(required: true),
      skip_confirm_option,
      CLEANUP_MODE_OPTION
    ].freeze
    DESCRIPTION = "Deletes or stops stale apps based on the latest image's creation date"
    LONG_DESCRIPTION = <<~DESC
      - Acts on stale apps based on the creation date of the latest image, or the GVC if no images exist
      - With `--mode=delete` (default): deletes the whole app (GVC with all workloads, all volumesets and all images), and unbinds the app from the secrets policy and any configured `shared_secret_grants` policies as long as both the identity and each policy exist (and are bound)
      - With `--mode=stop`: suspends all workloads via `cpflow ps:stop` — no GVC, volumeset, or image is removed; resume with `cpflow ps:start`
      - `--mode=stop` only suspends workloads listed in `app_workloads` + `additional_workloads`; workloads present in the live GVC but missing from the config are skipped silently
      - `--mode=stop` returns once each workload is marked suspended; it does not wait for the workload to reach a not-ready state
      - Specify the amount of days after an app should be considered stale through `stale_app_image_deployed_days` in the `.controlplane/controlplane.yml` file
      - If `match_if_app_name_starts_with` is `true` in the `.controlplane/controlplane.yml` file, it will act on all stale apps that start with the name
      - Will ask for explicit user confirmation
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Deletes stale apps (default).
      cpflow cleanup-stale-apps -a $APP_NAME

      # Stops stale apps instead of deleting them; resume with `cpflow ps:start`.
      cpflow cleanup-stale-apps -a $APP_NAME --mode=stop
      ```
    EX

    def call # rubocop:disable Metrics/MethodLength
      return progress.puts("No stale apps found.") if stale_apps.empty?

      progress.puts("Stale apps:")
      stale_apps.each do |app|
        progress.puts("  - #{app[:name]} (#{Shell.color(app[:date].to_s, :red)})")
      end

      return unless confirm_action

      progress.puts
      stale_apps.each do |app|
        process_app(app[:name])
        progress.puts
      end
    end

    private

    def stale_apps # rubocop:disable Metrics/MethodLength
      @stale_apps ||=
        begin
          apps = []

          now = DateTime.now
          stale_app_image_deployed_days = config[:stale_app_image_deployed_days]

          gvcs = cp.gvc_query(config.app)["items"]
          gvcs.each do |gvc|
            app_name = gvc["name"]

            images = cp.query_images(app_name)["items"].select { |item| item["name"].start_with?("#{app_name}:") }
            image = cp.latest_image_from(images, app_name: app_name, name_only: false)

            created_at = image ? image["created"] : gvc["created"]
            next unless created_at

            created_date = DateTime.parse(created_at)
            diff_in_days = (now - created_date).to_i
            next unless diff_in_days >= stale_app_image_deployed_days

            apps.push({
                        name: app_name,
                        date: created_date
                      })
          end

          apps
        end
    end

    def confirm_action
      return true if config.options[:yes]

      Shell.confirm("\nAre you sure you want to #{action_description} these #{stale_apps.length} apps?")
    end

    def process_app(app)
      if mode == "stop"
        progress.puts("Stopping app '#{app}'")
        stop_configured_live_workloads(app)
      else
        run_cpflow_command("delete", "-a", app, "--yes")
      end
    end

    def stop_configured_live_workloads(app)
      app_config = config.find_app_config(app)
      raise "Can't find config for stale app '#{app}'." unless app_config

      configured_workloads = required_app_option(app_config, app, :app_workloads) +
                             required_app_option(app_config, app, :additional_workloads)
      live_workloads = cp.fetch_workloads(app).fetch("items", []).map { |workload| workload.fetch("name") }

      (configured_workloads & live_workloads).each do |workload|
        run_cpflow_command("ps:stop", "-a", app, "--workload", workload)
      end
    end

    def required_app_option(app_config, app, option)
      raise "Can't find option '#{option}' for app '#{app}' in 'controlplane.yml'." unless app_config.key?(option)

      app_config.fetch(option)
    end

    def action_description
      mode == "stop" ? "suspend all workloads in" : "delete"
    end

    def mode
      @mode ||= config.options[:mode]
    end
  end
end
