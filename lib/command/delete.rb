# frozen_string_literal: true

module Command
  class Delete < Base
    NAME = "delete"
    OPTIONS = [
      app_option(required: true),
      skip_confirm_option
    ].freeze
    DESCRIPTION = "Deletes the whole app (GVC with all workloads and all images)"
    LONG_DESCRIPTION = <<~HEREDOC
      - Deletes the whole app (GVC with all workloads and all images)
      - Will ask for explicit user confirmation
    HEREDOC

    def call
      return unless confirm_delete

      delete_gvc
      delete_images
    end

    private

    def confirm_delete
      return true if config.options[:yes]

      confirmed = Shell.confirm("Are you sure you want to delete '#{config.app}'?")
      return false unless confirmed

      progress.puts
      true
    end

    def delete_gvc
      progress.puts "- Deleting gvc:"

      return progress.puts "none" unless cp.gvc_get

      cp.gvc_delete
      progress.puts config.app
    end

    def delete_images
      progress.puts "- Deleting image(s):"

      images = cp.image_query["items"]
                 .filter_map { |item| item["name"] if item["name"].start_with?("#{config.app}:") }

      return progress.puts "none" unless images

      images.each do |image|
        cp.image_delete(image)
        progress.puts image
      end
    end
  end
end
