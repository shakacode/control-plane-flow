# frozen_string_literal: true

module Command
  class Promote < Base
    def call
      image = latest_image

      config[:app_workloads].each do |workload|
        # NOTE: atm, container name == workload name (maybe need better logic here)
        cp.workload_set_image_ref(workload, container: workload, image: image)
      end
    end
  end
end
