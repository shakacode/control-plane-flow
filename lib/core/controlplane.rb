# frozen_string_literal: true

class Controlplane # rubocop:disable Metrics/ClassLength
  attr_reader :config, :api, :gvc, :org

  def initialize(config)
    @config = config
    @api = ControlplaneApi.new
    @gvc = config.app
    @org = config[:cpln_org]
  end

  # image

  def image_build(image, dockerfile:, push: true)
    cmd = "cpln image build --org #{org} --name #{image} --dir #{config.app_dir} --dockerfile #{dockerfile}"
    cmd += " --push" if push
    perform(cmd)
  end

  def image_query(app_name = config.app)
    cmd = "cpln image query --org #{org} -o yaml --max -1 --prop repository=#{app_name}"
    perform_yaml(cmd)
  end

  def image_delete(image)
    api.image_delete(org: org, image: image)
  end

  # gvc

  def gvc_query(app_name = config.app)
    # When `match_if_app_name_starts_with` is `true`, we query for any gvc containing the name,
    # otherwise we query for a gvc with the exact name.
    op = config.current[:match_if_app_name_starts_with] ? "~" : "="

    cmd = "cpln gvc query --org #{org} -o yaml --prop name#{op}#{app_name}"
    perform_yaml(cmd)
  end

  def fetch_gvc(a_gvc = gvc)
    api.gvc_get(gvc: a_gvc, org: org)
  end

  def fetch_gvc!(a_gvc = gvc)
    gvc_data = fetch_gvc(a_gvc)
    return gvc_data if gvc_data

    Shell.abort("Can't find GVC '#{gvc}', please create it with 'cpl setup gvc -a #{config.app}'.")
  end

  def gvc_delete(a_gvc = gvc)
    api.gvc_delete(gvc: a_gvc, org: org)
  end

  # workload

  def fetch_workload(workload)
    api.workload_get(workload: workload, gvc: gvc, org: org)
  end

  def fetch_workload!(workload)
    workload_data = fetch_workload(workload)
    return workload_data if workload_data

    Shell.abort("Can't find workload '#{workload}', please create it with 'cpl setup #{workload} -a #{config.app}'.")
  end

  def workload_get_replicas(workload, location:)
    cmd = "cpln workload get-replicas #{workload} #{gvc_org} --location #{location} -o yaml"
    perform_yaml(cmd)
  end

  def workload_set_image_ref(workload, container:, image:)
    cmd = "cpln workload update #{workload} #{gvc_org}"
    cmd += " --set spec.containers.#{container}.image=/org/#{config[:cpln_org]}/image/#{image}"
    perform(cmd)
  end

  def workload_set_suspend(workload, value)
    data = fetch_workload!(workload)
    data["spec"]["defaultOptions"]["suspend"] = value
    apply(data)
  end

  def workload_force_redeployment(workload)
    cmd = "cpln workload force-redeployment #{workload} #{gvc_org}"
    perform(cmd)
  end

  def workload_delete(workload, no_raise: false)
    cmd = "cpln workload delete #{workload} #{gvc_org}"
    cmd += " 2> /dev/null" if no_raise
    no_raise ? perform_no_raise(cmd) : perform(cmd)
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

  private

  def perform(cmd)
    system(cmd) || exit(false)
  end

  def perform_no_raise(cmd)
    system(cmd)
  end

  def perform_yaml(cmd)
    result = `#{cmd}`
    $?.success? ? YAML.safe_load(result) : exit(false) # rubocop:disable Style/SpecialGlobalVars
  end

  def gvc_org
    "--gvc #{gvc} --org #{org}"
  end
end
