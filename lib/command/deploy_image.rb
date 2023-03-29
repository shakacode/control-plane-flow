# frozen_string_literal: true

module Command
  class DeployImage < Base
    NAME = "deploy-image"
    OPTIONS = [
      app_option(required: true)
    ].freeze
    DESCRIPTION = "Deploys the latest image to app workloads"
    LONG_DESCRIPTION = <<~DESC
      - Deploys the latest image to app workloads
    DESC

    def call
      image = latest_image

      config[:app_workloads].each do |workload|
        cp.fetch_workload!(workload).dig("spec", "containers").each do |container|
          next unless container["image"].match?(%r{^/org/#{config.org}/image/#{config.app}:})

          step("Deploying image '#{image}' for workload '#{container['name']}'") do
            cp.workload_set_image_ref(workload, container: container["name"], image: image)
          end
        end
      end
    end
  end
end
