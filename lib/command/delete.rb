# frozen_string_literal: true

module Command
  class Delete < Base
    NAME = "delete"
    OPTIONS = [
      app_option(required: true),
      skip_confirm_option
    ].freeze
    DESCRIPTION = "Deletes the whole app (GVC with all workloads, all volumesets and all images)"
    LONG_DESCRIPTION = <<~DESC
      - Deletes the whole app (GVC with all workloads, all volumesets and all images)
      - Will ask for explicit user confirmation
    DESC

    def call
      return progress.puts("App '#{config.app}' does not exist.") if cp.fetch_gvc.nil?

      check_volumesets
      check_images
      return unless confirm_delete

      delete_volumesets
      delete_gvc
      delete_images
    end

    private

    def check_volumesets
      @volumesets = cp.fetch_volumesets["items"]
      return progress.puts("No volumesets to delete.") unless @volumesets.any?

      message = "The following volumesets will be deleted along with the app:"
      volumesets_list = @volumesets.map { |volumeset| "- #{volumeset['name']}" }.join("\n")
      progress.puts("#{Shell.color(message, :red)}\n#{volumesets_list}\n\n")
    end

    def check_images
      @images = cp.query_images["items"]
                  .select { |image| image["name"].start_with?("#{config.app}:") }
      return progress.puts("No images to delete.") unless @images.any?

      message = "The following images will be deleted along with the app:"
      images_list = @images.map { |image| "- #{image['name']}" }.join("\n")
      progress.puts("#{Shell.color(message, :red)}\n#{images_list}\n\n")
    end

    def confirm_delete
      return true if config.options[:yes]

      confirmed = Shell.confirm("Are you sure you want to delete '#{config.app}'?")
      return false unless confirmed

      progress.puts
      true
    end

    def delete_gvc
      step("Deleting app '#{config.app}'") do
        cp.gvc_delete
      end
    end

    def delete_volumesets
      @volumesets.each do |volumeset|
        step("Deleting volumeset '#{volumeset['name']}'") do
          # If the volumeset is attached to a workload, we need to delete the workload first
          workload = volumeset.dig("status", "usedByWorkload")&.split("/")&.last
          cp.delete_workload(workload) if workload

          cp.delete_volumeset(volumeset["name"])
        end
      end
    end

    def delete_images
      @images.each do |image|
        step("Deleting image '#{image['name']}'") do
          cp.image_delete(image["name"])
        end
      end
    end
  end
end
