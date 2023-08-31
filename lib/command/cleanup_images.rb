# frozen_string_literal: true

module Command
  class CleanupImages < Base # rubocop:disable Metrics/ClassLength
    NAME = "cleanup-images"
    OPTIONS = [
      app_option(required: true),
      skip_confirm_option
    ].freeze
    DESCRIPTION = <<~DESC
      Deletes all images for an app that either exceed the max quantity or are older than the specified amount of days
    DESC
    LONG_DESCRIPTION = <<~DESC
      - Deletes all images for an app that either exceed the max quantity or are older than the specified amount of days
      - Specify the max quantity through `image_retention_max_qty` in the `.controlplane/controlplane.yml` file
      - Specify the amount of days through `image_retention_days` in the `.controlplane/controlplane.yml` file
      - If `image_retention_max_qty` is specified, any images that exceed it will be deleted, regardless of `image_retention_days`
      - Will ask for explicit user confirmation
      - Never deletes the latest image
    DESC

    def call # rubocop:disable Metrics/MethodLength
      ensure_max_qty_or_days!

      return progress.puts("No images to delete.") if images_to_delete.empty?

      progress.puts("Images to delete:")
      images_to_delete.each do |image|
        created = Shell.color((image[:created]).to_s, :red)
        reason = Shell.color(image[:reason], :red)
        progress.puts("  - #{image[:name]} (#{created} - #{reason})")
      end

      return unless confirm_delete

      progress.puts
      delete_images
    end

    private

    def ensure_max_qty_or_days!
      @image_retention_max_qty = config.current[:image_retention_max_qty]
      @image_retention_days = config.current[:image_retention_days]
      return if @image_retention_max_qty || @image_retention_days

      raise "Can't find either option 'image_retention_max_qty' or 'image_retention_days' " \
            "for app '#{@config.app}' in 'controlplane.yml'."
    end

    def app_prefix
      config.should_app_start_with?(config.app) ? "#{config.app}-" : "#{config.app}:"
    end

    def remove_deployed_image(app, images)
      return images unless cp.fetch_gvc(app)

      # If app exists, remove latest image, because we don't want to delete the image that is currently deployed
      latest_image_name = latest_image_from(images, app_name: app)
      images.reject { |image| image["name"] == latest_image_name }
    end

    def parse_images_and_sort_by_created(images)
      images = images.map do |image|
        {
          name: image["name"],
          created: DateTime.parse(image["created"])
        }
      end
      images.sort_by { |image| image[:created] }
    end

    def add_reason_to_images(images, reason)
      images.map do |image|
        {
          **image,
          reason: reason
        }
      end
    end

    def filter_images_by_max_qty(images)
      return [], images unless @image_retention_max_qty && images.length > @image_retention_max_qty

      split_index = images.length - @image_retention_max_qty
      excess_images = images[0...split_index]
      remaining_images = images[split_index...]
      excess_images = add_reason_to_images(excess_images, "exceeds max quantity of #{@image_retention_max_qty}")

      [excess_images, remaining_images]
    end

    def filter_images_by_days(images)
      return [] unless @image_retention_days

      now = DateTime.now
      old_images = images.select { |image| (now - image[:created]).to_i >= @image_retention_days }
      add_reason_to_images(old_images, "older than #{@image_retention_days} days")
    end

    def images_to_delete # rubocop:disable Metrics/MethodLength
      @images_to_delete ||=
        begin
          result_images = []

          images = cp.query_images["items"].select { |item| item["name"].start_with?(app_prefix)	}
          images_by_app = images.group_by { |item| item["repository"] }
          images_by_app.each do |app, app_images|
            app_images = remove_deployed_image(app, app_images)
            app_images = parse_images_and_sort_by_created(app_images)
            excess_images, remaining_images = filter_images_by_max_qty(app_images)
            old_images = filter_images_by_days(remaining_images)

            result_images += excess_images
            result_images += old_images
          end

          result_images
        end
    end

    def confirm_delete
      return true if config.options[:yes]

      Shell.confirm("\nAre you sure you want to delete these #{images_to_delete.length} images?")
    end

    def delete_images
      images_to_delete.each do |image|
        step("Deleting image '#{image[:name]}'") do
          cp.image_delete(image[:name])
        end
      end
    end
  end
end
