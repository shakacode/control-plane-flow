# frozen_string_literal: true

module Command
  class Build < Base
    def call
      abort("ERROR: atm for review apps only") unless config.review_app?

      cp.build_image(image: image)

      config.review_apps[:workloads].each do |workload|
        cp.update_image_ref(workload: workload, image: image)
        cp.force_redeployment(workload: workload) if image.match(/:latest$/)
      end
    end

    private

    def cp
      @cp ||= Controlplane.new(config, org: config.review_apps.fetch(:org))
    end

    def image
      cp.review_app_image
    end
  end
end
