# frozen_string_literal: true

require "yaml"
require "open3"

class Controlplane
  attr_reader :config, :org

  def initialize(config, org:)
    @config = config
    @org = org
  end

  def app_dir
    config.app_dir
  end

  def dockerfile
    config.dockerfile
  end

  def gvc
    config.options.fetch(:app)
  end

  def build_image(image:, push: true)
    cmd = "cpln image build --name #{image} --dir #{app_dir} --dockerfile #{dockerfile}"
    cmd += " --push" if push
    perform(cmd)
  end

  def update_image_ref(workload:, image:, container: nil)
    container ||= workload
    cmd = "cpln workload update #{workload}"
    cmd += " --set spec.containers.#{container}.image=/org/#{org}/image/#{image}"
    cmd += " --gvc #{gvc}"
    perform(cmd)
  end

  def force_redeployment(workload:)
    cmd = "cpln workload force-redeployment #{workload} --gvc #{gvc}"
    perform(cmd)
  end

  def review_app_image
    "#{gvc}:latest"
  end

  # def clone_workload(workload:, new_workload:)
  #   cmd = "cpln workload clone #{workload} --name #{new_workload} --gvc #{gvc} > /dev/null"
  #   perform(cmd)
  # end

  def delete_workload(workload)
    # TODO: check if workload exists before deleting
    cmd = "cpln workload delete #{workload} --gvc #{gvc} 2> /dev/null"
    perform(cmd)
  end

  def connect_workload(workload, location:, runner: nil)
    cmd = "cpln workload connect #{workload} --gvc #{gvc} --location #{location}"
    cmd += " -c #{runner}" if runner
    perform(cmd)
  end

  def get_workload(workload)
    result = `cpln workload get #{workload} --gvc #{gvc} -o yaml`
    YAML.safe_load(result)
  end

  def get_replicas(workload, location:)
    cmd = "cpln workload get-replicas #{workload} --location #{location} --gvc #{gvc} -o yaml 2> /dev/null"
    YAML.safe_load(`#{cmd}`)
  end

  def apply(data)
    cmd = "cpln apply --gvc #{gvc} -v -d --file -"
    Open3.capture3(cmd, stdin_data: data.to_yaml)
  end

  def show_logs(workload)
    cmd = "cpln logs '{workload=\"#{workload}\"}' -t -o raw"
    perform(cmd)
  end

  private

  def perform(cmd)
    # puts cmd
    system(cmd)
  end
end
