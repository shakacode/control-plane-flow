# frozen_string_literal: true

module Command
  class Build < Base
    def call
      abort("ERROR: atm only :latest image_tagging implemented") if config[:image_tagging] != "latest"

      image = "#{config.app}:latest"
      dockerfile = "#{config.app_cpln_dir}/Dockerfile"

      cp.image_build(image, dockerfile: dockerfile)

      config[:app_workloads].each do |workload|
        # NOTE: atm, container name == workload name (maybe need better logic here)
        cp.workload_set_image_ref(workload, container: workload, image: image)
        cp.workload_force_redeployment(workload) if config[:image_tagging] == "latest"
      end
    end
  end
end
