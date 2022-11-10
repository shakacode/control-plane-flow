# frozen_string_literal: true

class Controlplane
  attr_reader :config, :api

  def initialize(config)
    @config = config
    @api = ControlplaneApi.new
  end

  # image

  def image_build(image, dockerfile:, push: true)
    cmd = "cpln image build --name #{image} --dir #{config.app_dir} --dockerfile #{dockerfile}"
    cmd += " --push" if push
    perform(cmd)
  end

  # gvc

  def gvc_get(a_gvc = gvc)
    api.gvc_get(gvc: a_gvc, org: org)
  end

  # workload

  def workload_get(workload)
    api.workload_get(workload: workload, gvc: gvc, org: org)
  end

  def workload_get_replicas(workload, location:)
    cmd = "cpln workload get-replicas #{workload} #{gvc_org} --location #{location} -o yaml 2> /dev/null"
    perform(cmd, result: :yaml)
  end

  def workload_set_image_ref(workload, container:, image:)
    cmd = "cpln workload update #{workload} #{gvc_org}"
    cmd += " --set spec.containers.#{container}.image=/org/#{config[:org]}/image/#{image}"
    perform(cmd)
  end

  def workload_set_suspend(workload, value)
    data = workload_get(workload)
    data["spec"]["defaultOptions"]["suspend"] = value
    apply(data)
  end

  def workload_force_redeployment(workload)
    cmd = "cpln workload force-redeployment #{workload} #{gvc_org}"
    perform(cmd)
  end

  def workload_delete(workload)
    cmd = "cpln workload delete #{workload} #{gvc_org} 2> /dev/null"
    perform(cmd)
  end

  def workload_connect(workload, location:, container: nil, shell: nil)
    cmd = "cpln workload connect #{workload} #{gvc_org} --location #{location}"
    cmd += " --container #{container}" if container
    cmd += " --shell #{shell}" if shell
    perform(cmd)
  end

  def workload_exec(workload, location:, container: nil, command: nil)
    cmd = "cpln workload exec #{workload} #{gvc_org} --location #{location}"
    cmd += " --container #{container}" if container
    cmd += " -- #{command}"
    perform(cmd)
  end

  # logs

  def logs(workload:)
    cmd = "cpln logs '{workload=\"#{workload}\"}' --org #{org} -t -o raw --limit 200"
    perform(cmd)
  end

  def log_get(workload:, from:, to:)
    api.log_get(org: org, gvc: gvc, workload: workload, from: from, to: to)
  end

  # apply

  def apply(data)
    Tempfile.create do |f|
      f.write(data.to_yaml)
      f.rewind
      cmd = "cpln apply #{gvc_org} --file #{f.path} > /dev/null"
      perform(cmd)
    end
  end

  # props

  def gvc
    config.app
  end

  def org
    config[:org]
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

  def gvc_org
    "--gvc #{gvc} --org #{org}"
  end
end
