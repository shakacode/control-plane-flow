# frozen_string_literal: true

require "yaml"
require "open3"

class Controlplane
  attr_reader :config

  def initialize(config)
    @config = config
  end

  def build_image(image:, dockerfile:, push: true)
    cmd = "cpln image build --name #{image} --dir #{config.app_dir} --dockerfile #{dockerfile}"
    cmd += " --push" if push
    perform(cmd)
  end

  def update_image_ref(workload:, image:, container: nil)
    container ||= workload
    cmd = "cpln workload update #{workload}"
    cmd += " --set spec.containers.#{container}.image=/org/#{config[:org]}/image/#{image}"
    cmd += " --gvc #{gvc}"
    perform(cmd)
  end

  def force_redeployment(workload:)
    cmd = "cpln workload force-redeployment #{workload} --gvc #{gvc}"
    perform(cmd)
  end

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
    cmd = "cpln workload get #{workload} --gvc #{gvc} -o yaml"
    perform(cmd, result: :yaml)
  end

  def get_replicas(workload, location:)
    cmd = "cpln workload get-replicas #{workload} --location #{location} --gvc #{gvc} -o yaml 2> /dev/null"
    perform(cmd, result: :yaml)
  end

  def apply(data)
    cmd = "cpln apply --gvc #{gvc} -v -d --file -"
    Open3.capture3(cmd, stdin_data: data.to_yaml)
  end

  def show_logs(workload)
    cmd = "cpln logs '{workload=\"#{workload}\"}' -t -o raw"
    perform(cmd)
  end

  def set_workload_suspend(workload, value)
    yaml = get_workload(workload)
    yaml["spec"]["defaultOptions"]["suspend"] = value
    apply(yaml)
  end

  private

  def perform(cmd, result: nil)
    # puts cmd
    case result
    when nil then system(cmd)
    when :yaml then YAML.safe_load(`#{cmd}`)
    else raise("Unknown result type '#{result}'")
    end
  end

  def gvc
    config.app
  end
end
