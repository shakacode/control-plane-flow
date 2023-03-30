# frozen_string_literal: true

require "date"

module Command
  class CleanupStaleApps < Base
    NAME = "cleanup-stale-apps"
    OPTIONS = [
      app_option(required: true),
      skip_confirm_option
    ].freeze
    DESCRIPTION = "Deletes the whole app (GVC with all workloads and all images) for all stale apps"
    LONG_DESCRIPTION = <<~DESC
      - Deletes the whole app (GVC with all workloads and all images) for all stale apps
      - Stale apps are identified based on the creation date of the latest image
      - Specify the amount of days after an app should be considered stale through `stale_app_image_deployed_days` in the `.controlplane/controlplane.yml` file
      - If `match_if_app_name_starts_with` is `true` in the `.controlplane/controlplane.yml` file, it will delete all stale apps that start with the name
      - Will ask for explicit user confirmation
    DESC

    def call # rubocop:disable Metrics/MethodLength
      return progress.puts("No stale apps found.") if stale_apps.empty?

      progress.puts("Stale apps:")
      stale_apps.each do |app|
        progress.puts("  #{app[:name]} (#{Shell.color((app[:date]).to_s, :red)})")
      end

      return unless confirm_delete

      progress.puts
      stale_apps.each do |app|
        delete_gvc(app)
        delete_images(app)
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

            images = cp.image_query(app_name)["items"].filter { |item| item["name"].start_with?("#{app_name}:") }
            image = latest_image_from(images, app_name: app_name, name_only: false)

            created_date = DateTime.parse(image["created"])
            diff_in_days = (now - created_date).to_i
            next unless diff_in_days >= stale_app_image_deployed_days

            apps.push({
                        name: app_name,
                        date: created_date,
                        images: images.map { |current_image| current_image["name"] }
                      })
          end

          apps
        end
    end

    def confirm_delete
      return true if config.options[:yes]

      Shell.confirm("\nAre you sure you want to delete these #{stale_apps.length} apps?")
    end

    def delete_gvc(app)
      step("Deleting app '#{app[:name]}'") do
        cp.gvc_delete(app[:name])
      end
    end

    def delete_images(app)
      app[:images].each do |image|
        step("Deleting image '#{image}'") do
          cp.image_delete(image)
        end
      end
    end
  end
end
