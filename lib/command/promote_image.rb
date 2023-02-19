# frozen_string_literal: true

module Command
  class PromoteImage < Base
    NAME = "promote-image"
    OPTIONS = [
      app_option(required: true)
    ].freeze
    DESCRIPTION = "Promotes the latest image to app workloads"
    LONG_DESCRIPTION = <<~HEREDOC
      - Promotes the latest image to app workloads
    HEREDOC

    def call
      image = latest_image

      config[:app_workloads].each do |workload|
        cp.workload_get(workload).dig("spec", "containers").each do |container|
          next unless container["image"].match?(%r{^/org/#{config[:cpln_org]}/image/#{config.app}:})

          cp.workload_set_image_ref(workload, container: container["name"], image: image)
          progress.puts "updated #{container['name']}"
        end
      end
    end
  end
end
