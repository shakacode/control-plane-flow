# frozen_string_literal: true

module Command
  class Build < Base
    def call
      abort("ERROR: atm only :latest image_tagging implemented") if config[:image_tagging] != "latest"

      image = "#{config.app}:latest"
      dockerfile = "#{config.app_cpln_dir}/Dockerfile"

      cp.build_image(image: image, dockerfile: dockerfile)

      config[:app_workloads].each do |workload|
        cp.update_image_ref(workload: workload, image: image)
        cp.force_redeployment(workload: workload) if config[:image_tagging] == "latest"
      end
    end
  end
end
