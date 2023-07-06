# frozen_string_literal: true

module Command
  class CleanupOldImages < Base
    NAME = "cleanup-old-images"
    OPTIONS = [
      app_option(required: true),
      skip_confirm_option
    ].freeze
    DESCRIPTION = "Deletes all images for an app that are older than the specified amount of days"
    LONG_DESCRIPTION = <<~DESC
      - Deletes all images for an app that are older than the specified amount of days
      - Specify the amount of days through `old_image_retention_days` in the `.controlplane/controlplane.yml` file
      - Will ask for explicit user confirmation
      - Does not affect the latest image, regardless of how old it is
    DESC

    def call
      return progress.puts("No old images found.") if old_images.empty?

      progress.puts("Old images:")
      old_images.each do |image|
        progress.puts("  - #{image[:name]} (#{Shell.color((image[:date]).to_s, :red)})")
      end

      return unless confirm_delete

      progress.puts
      delete_images
    end

    private

    def app_prefix
      config.should_app_start_with?(config.app) ? "#{config.app}-" : "#{config.app}:"
    end

    def remove_deployed_image(app, app_images)
      return app_images unless cp.fetch_gvc(app)

      # If app exists, remove latest image, because we don't want to delete the image that is currently deployed
      latest_image_name = latest_image_from(app_images, app_name: app)
      app_images.filter { |item| item["name"] != latest_image_name }
    end

    def old_images # rubocop:disable Metrics/MethodLength
      @old_images ||=
        begin
          result_images = []

          now = DateTime.now
          old_image_retention_days = config[:old_image_retention_days]

          images = cp.image_query["items"].filter { |item| item["name"].start_with?(app_prefix)	}
          images_by_app = images.group_by { |item| item["repository"] }
          images_by_app.each do |app, app_images|
            app_images = remove_deployed_image(app, app_images)
            app_images.each do |image|
              created_date = DateTime.parse(image["created"])
              diff_in_days = (now - created_date).to_i
              next unless diff_in_days >= old_image_retention_days

              result_images.push({
                                   name: image["name"],
                                   date: created_date
                                 })
            end
          end

          result_images
        end
    end

    def confirm_delete
      return true if config.options[:yes]

      Shell.confirm("\nAre you sure you want to delete these #{old_images.length} images?")
    end

    def delete_images
      old_images.each do |image|
        step("Deleting image '#{image[:name]}'") do
          cp.image_delete(image[:name])
        end
      end
    end
  end
end
