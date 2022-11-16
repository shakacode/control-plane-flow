# frozen_string_literal: true

module Command
  class Delete < Base
    def call
      progress.puts "Type 'delete' to delete #{config.app} and images"
      progress.print "> "

      return progress.puts "Not confirmed" unless $stdin.gets.chomp == "delete"

      delete_gvc
      delete_images
    end

    private

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
