# frozen_string_literal: true

class Controlplane # rubocop:disable Metrics/ClassLength
  attr_reader :config, :api, :gvc, :org

  NO_IMAGE_AVAILABLE = "NO_IMAGE_AVAILABLE"

  def initialize(config)
    @config = config
    @api = ControlplaneApi.new
    @gvc = config.app
    @org = config.org

    ensure_org_exists! if org
  end

  # profile

  def profile_switch(profile)
    ENV["CPLN_PROFILE"] = profile
    ControlplaneApiDirect.reset_api_token
  end

  def profile_exists?(profile)
    cmd = "cpln profile get #{profile} -o yaml"
    perform_yaml!(cmd).length.positive?
  end

  def profile_create(profile, token)
    sensitive_data_pattern = /(?<=--token )(\S+)/
    cmd = "cpln profile create #{profile} --token #{token}"
    perform!(cmd, sensitive_data_pattern: sensitive_data_pattern)
  end

  def profile_delete(profile)
    cmd = "cpln profile delete #{profile}"
    perform!(cmd)
  end

  # image

  def latest_image(a_gvc = gvc, a_org = org, refresh: false)
    @latest_image ||= {}
    @latest_image[a_gvc] = nil if refresh
    @latest_image[a_gvc] ||=
      begin
        items = query_images(a_gvc, a_org)["items"]
        latest_image_from(items, app_name: a_gvc)
      end
  end

  def latest_image_next(a_gvc = gvc, a_org = org, commit: nil)
    commit ||= config.options[:commit]

    @latest_image_next ||= {}
    @latest_image_next[a_gvc] ||= begin
      latest_image_name = latest_image(a_gvc, a_org)
      image = latest_image_name.split(":").first
      image += ":#{extract_image_number(latest_image_name) + 1}"
      image += "_#{commit}" if commit
      image
    end
  end

  def latest_image_from(items, app_name: gvc, name_only: true)
    matching_items = items.select { |item| item["name"].start_with?("#{app_name}:") }

    # Or special string to indicate no image available
    if matching_items.empty?
      name_only ? "#{app_name}:#{NO_IMAGE_AVAILABLE}" : nil
    else
      latest_item = matching_items.max_by { |item| extract_image_number(item["name"]) }
      name_only ? latest_item["name"] : latest_item
    end
  end

  def extract_image_number(image_name)
    return 0 if image_name.end_with?(NO_IMAGE_AVAILABLE)

    image_name.match(/:(\d+)/)&.captures&.first.to_i
  end

  def extract_image_commit(image_name)
    image_name.match(/_(\h+)$/)&.captures&.first
  end

  def query_images(a_gvc = gvc, a_org = org, partial_gvc_match: nil)
    partial_gvc_match = config.should_app_start_with?(a_gvc) if partial_gvc_match.nil?
    gvc_op = partial_gvc_match ? "~" : "="

    api.query_images(org: a_org, gvc: a_gvc, gvc_op_type: gvc_op)
  end

  def image_build(image, dockerfile:, docker_args: [], build_args: [], push: true)
    # https://docs.controlplane.com/guides/push-image#step-2
    # Might need to use `docker buildx build` if compatiblitity issues arise
    cmd = "docker build --platform=linux/amd64 -t #{image} -f #{dockerfile}"
    cmd += " --progress=plain" if ControlplaneApiDirect.trace

    cmd += " #{docker_args.join(' ')}" if docker_args.any?
    build_args.each { |build_arg| cmd += " --build-arg #{build_arg}" }
    cmd += " #{config.app_dir}"
    perform!(cmd)

    image_push(image) if push
  end

  def fetch_image_details(image)
    api.fetch_image_details(org: org, image: image)
  end

  def image_delete(image)
    api.image_delete(org: org, image: image)
  end

  def image_login(org_name = config.org)
    cmd = "cpln image docker-login --org #{org_name}"
    perform!(cmd, output_mode: :none)
  end

  def image_pull(image)
    cmd = "docker pull #{image}"
    perform!(cmd, output_mode: :none)
  end

  def image_tag(old_tag, new_tag)
    cmd = "docker tag #{old_tag} #{new_tag}"
    perform!(cmd)
  end

  def image_push(image)
    cmd = "docker push #{image}"
    perform!(cmd)
  end

  # gvc

  def fetch_gvcs
    api.gvc_list(org: org)
  end

  def gvc_query(app_name = config.app)
    # When `match_if_app_name_starts_with` is `true`, we query for any gvc containing the name,
    # otherwise we query for a gvc with the exact name.
    op = config.should_app_start_with?(app_name) ? "~" : "="

    cmd = "cpln gvc query --org #{org} -o yaml --prop name#{op}#{app_name}"
    perform_yaml!(cmd)
  end

  def fetch_gvc(a_gvc = gvc, a_org = org)
    api.gvc_get(gvc: a_gvc, org: a_org)
  end

  def fetch_gvc!(a_gvc = gvc)
    gvc_data = fetch_gvc(a_gvc)
    return gvc_data if gvc_data

    raise "Can't find app '#{gvc}', please create it with 'cpl setup-app -a #{config.app}'."
  end

  def gvc_delete(a_gvc = gvc)
    api.gvc_delete(gvc: a_gvc, org: org)
  end

  # workload

  def fetch_workloads(a_gvc = gvc)
    api.workload_list(gvc: a_gvc, org: org)
  end

  def fetch_workloads_by_org(a_org = org)
    api.workload_list_by_org(org: a_org)
  end

  def fetch_workload(workload)
    api.workload_get(workload: workload, gvc: gvc, org: org)
  end

  def fetch_workload!(workload)
    workload_data = fetch_workload(workload)
    return workload_data if workload_data

    raise "Can't find workload '#{workload}', please create it with 'cpl apply-template #{workload} -a #{config.app}'."
  end

  def query_workloads(workload, a_gvc = gvc, a_org = org, partial_workload_match: false, partial_gvc_match: nil)
    partial_gvc_match = config.should_app_start_with?(a_gvc) if partial_gvc_match.nil?
    gvc_op = partial_gvc_match ? "~" : "="
    workload_op = partial_workload_match ? "~" : "="

    api.query_workloads(org: a_org, gvc: a_gvc, workload: workload, gvc_op_type: gvc_op, workload_op_type: workload_op)
  end

  def fetch_workload_replicas(workload, location:)
    cmd = "cpln workload replica get #{workload} #{gvc_org} --location #{location} -o yaml"
    perform_yaml(cmd)
  end

  def stop_workload_replica(workload, replica, location:)
    cmd = "cpln workload replica stop #{workload} #{gvc_org} --replica-name #{replica} --location #{location}"
    perform(cmd, output_mode: :none)
  end

  def fetch_workload_deployments(workload)
    api.workload_deployments(workload: workload, gvc: gvc, org: org)
  end

  def workload_deployment_version_ready?(version, next_version)
    return false unless version["workload"] == next_version

    version["containers"]&.all? do |_, container|
      container.dig("resources", "replicas") == container.dig("resources", "replicasReady")
    end
  end

  def workload_deployments_ready?(workload, location:, expected_status:)
    deployed_replicas = fetch_workload_replicas(workload, location: location)["items"].length
    return deployed_replicas.zero? if expected_status == false

    deployments = fetch_workload_deployments(workload)["items"]
    deployments.all? do |deployment|
      next_version = deployment.dig("status", "expectedDeploymentVersion")

      deployment.dig("status", "versions")&.all? do |version|
        workload_deployment_version_ready?(version, next_version)
      end
    end
  end

  def workload_set_image_ref(workload, container:, image:)
    cmd = "cpln workload update #{workload} #{gvc_org}"
    cmd += " --set spec.containers.#{container}.image=/org/#{config.org}/image/#{image}"
    perform!(cmd)
  end

  def set_workload_env_var(workload, container:, name:, value:)
    data = fetch_workload!(workload)
    data["spec"]["containers"].each do |container_data|
      next unless container_data["name"] == container

      container_data["env"].each do |env_data|
        next unless env_data["name"] == name

        env_data["value"] = value
      end
    end

    api.update_workload(org: org, gvc: gvc, workload: workload, data: data)
  end

  def set_workload_suspend(workload, value)
    data = fetch_workload!(workload)
    data["spec"]["defaultOptions"]["suspend"] = value

    api.update_workload(org: org, gvc: gvc, workload: workload, data: data)
  end

  def workload_force_redeployment(workload)
    cmd = "cpln workload force-redeployment #{workload} #{gvc_org}"
    perform!(cmd)
  end

  def delete_workload(workload, a_gvc = gvc)
    api.delete_workload(org: org, gvc: a_gvc, workload: workload)
  end

  def workload_connect(workload, location:, container: nil, shell: nil)
    cmd = "cpln workload connect #{workload} #{gvc_org} --location #{location}"
    cmd += " --container #{container}" if container
    cmd += " --shell #{shell}" if shell
    perform!(cmd, output_mode: :all)
  end

  def workload_exec(workload, replica, location:, container: nil, command: nil)
    cmd = "cpln workload exec #{workload} #{gvc_org} --replica #{replica} --location #{location}"
    cmd += " --container #{container}" if container
    cmd += " -- #{command}"
    perform!(cmd, output_mode: :all)
  end

  def start_cron_workload(workload, job_start_yaml, location:)
    Tempfile.create do |f|
      f.write(job_start_yaml)
      f.rewind

      cmd = "cpln workload cron start #{workload} #{gvc_org} --file #{f.path} --location #{location} -o yaml"
      perform_yaml(cmd)
    end
  end

  def fetch_cron_workload(workload, location:)
    cmd = "cpln workload cron get #{workload} #{gvc_org} --location #{location} -o yaml"
    perform_yaml(cmd)
  end

  def cron_workload_deployed_version(workload)
    current_deployment = fetch_workload_deployments(workload)&.dig("items")&.first
    return nil unless current_deployment

    ready = current_deployment.dig("status", "ready")
    last_processed_version = current_deployment.dig("status", "lastProcessedVersion")

    ready ? last_processed_version : nil
  end

  # volumeset

  def fetch_volumesets(a_gvc = gvc)
    api.list_volumesets(org: org, gvc: a_gvc)
  end

  def delete_volumeset(volumeset, a_gvc = gvc)
    api.delete_volumeset(org: org, gvc: a_gvc, volumeset: volumeset)
  end

  # domain

  def find_domain_route(data)
    port = data["spec"]["ports"].find { |current_port| current_port["number"] == 80 || current_port["number"] == 443 }
    return nil if port.nil? || port["routes"].nil?

    route = port["routes"].find { |current_route| current_route["prefix"] == "/" }
    return nil if route.nil?

    route
  end

  def find_domain_for(workloads)
    domains = api.list_domains(org: org)["items"]
    domains.find do |domain_data|
      route = find_domain_route(domain_data)
      next false if route.nil?

      workloads.any? { |workload| route["workloadLink"].match?(%r{/org/#{org}/gvc/#{gvc}/workload/#{workload}}) }
    end
  end

  def fetch_domain(domain)
    domain_data = api.fetch_domain(org: org, domain: domain)
    route = find_domain_route(domain_data)
    return nil if route.nil?

    domain_data
  end

  def domain_workload_matches?(data, workload)
    route = find_domain_route(data)
    route["workloadLink"].match?(%r{/org/#{org}/gvc/#{gvc}/workload/#{workload}})
  end

  def set_domain_workload(data, workload)
    route = find_domain_route(data)
    route["workloadLink"] = "/org/#{org}/gvc/#{gvc}/workload/#{workload}"

    api.update_domain(org: org, domain: data["name"], data: data)
  end

  # logs

  def logs(workload:, limit:, since:, replica: nil)
    query_parts = ["gvc=\"#{gvc}\"", "workload=\"#{workload}\""]
    query_parts.push("replica=\"#{replica}\"") if replica
    query = "{#{query_parts.join(',')}}"

    cmd = "cpln logs '#{query}' --org #{org} -t -o raw --limit #{limit} --since #{since}"
    perform!(cmd, output_mode: :all)
  end

  def log_get(workload:, from:, to:, replica: nil)
    api.log_get(org: org, gvc: gvc, workload: workload, replica: replica, from: from, to: to)
  end

  # identities

  def fetch_identity(identity, a_gvc = gvc)
    api.fetch_identity(org: org, gvc: a_gvc, identity: identity)
  end

  # policies

  def fetch_policy(policy)
    api.fetch_policy(org: org, policy: policy)
  end

  def bind_identity_to_policy(identity_link, policy)
    cmd = "cpln policy add-binding #{policy} --org #{org} --identity #{identity_link} --permission reveal"
    perform!(cmd)
  end

  def unbind_identity_from_policy(identity_link, policy)
    cmd = "cpln policy remove-binding #{policy} --org #{org} --identity #{identity_link} --permission reveal"
    perform!(cmd)
  end

  # apply
  def apply_template(data) # rubocop:disable Metrics/MethodLength
    Tempfile.create do |f|
      f.write(data)
      f.rewind
      cmd = "cpln apply #{gvc_org} --file #{f.path}"
      if Shell.tmp_stderr
        cmd += " 2> #{Shell.tmp_stderr.path}" if Shell.should_hide_output?

        Shell.debug("CMD", cmd)

        result = Shell.cmd(cmd)
        parse_apply_result(result[:output]) if result[:success]
      else
        Shell.debug("CMD", cmd)

        result = Shell.cmd(cmd)
        if result[:success]
          parse_apply_result(result[:output])
        else
          Shell.abort("Command exited with non-zero status.")
        end
      end
    end
  end

  def apply_hash(data)
    apply_template(data.to_yaml)
  end

  def parse_apply_result(result) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    items = []

    lines = result.split("\n")
    lines.each do |line|
      # The line can be in one of these formats:
      # - "Created /org/shakacode-open-source-examples/gvc/my-app-staging"
      # - "Created /org/shakacode-open-source-examples/gvc/my-app-staging/workload/redis"
      # - "Updated gvc 'tutorial-app-test-1'"
      # - "Updated workload 'redis'"
      if line.start_with?("Created")
        matches = line.match(%r{Created\s/org/[^/]+/gvc/([^/]+)($|(/([^/]+)/([^/]+)$))})&.captures
        next unless matches

        app, _, __, kind, name = matches
        if kind
          items.push({ kind: kind, name: name })
        else
          items.push({ kind: "app", name: app })
        end
      else
        matches = line.match(/Updated\s([^\s]+)\s'([^\s]+)'$/)&.captures
        next unless matches

        kind, name = matches
        kind = "app" if kind == "gvc"
        items.push({ kind: kind, name: name })
      end
    end

    items
  end

  private

  def org_exists?
    items = api.list_orgs["items"]
    items.any? { |item| item["name"] == org }
  end

  def ensure_org_exists!
    return if org_exists?

    raise "Can't find org '#{org}', please create it in the Control Plane dashboard " \
          "or ensure that the name is correct."
  end

  # `output_mode` can be :all, :errors_only or :none.
  # If not provided, it will be determined based on the `HIDE_COMMAND_OUTPUT` env var
  # or the return value of `Shell.should_hide_output?`.
  def build_command(cmd, output_mode: nil) # rubocop:disable Metrics/MethodLength
    output_mode ||= determine_command_output_mode

    case output_mode
    when :all
      cmd
    when :errors_only
      "#{cmd} > /dev/null"
    when :none
      "#{cmd} > /dev/null 2>&1"
    else
      raise "Invalid command output mode '#{output_mode}'."
    end
  end

  def determine_command_output_mode
    if ENV.fetch("HIDE_COMMAND_OUTPUT", nil) == "true"
      :none
    elsif Shell.should_hide_output?
      :errors_only
    else
      :all
    end
  end

  def perform(cmd, output_mode: nil, sensitive_data_pattern: nil)
    cmd = build_command(cmd, output_mode: output_mode)

    Shell.debug("CMD", cmd, sensitive_data_pattern: sensitive_data_pattern)

    kernel_system_with_pid_handling(cmd)
  end

  # NOTE: full analogue of Kernel.system which returns pids and saves it to child_pids for proper killing
  def kernel_system_with_pid_handling(cmd)
    pid = Process.spawn(cmd)
    $child_pids << pid # rubocop:disable Style/GlobalVars

    _, status = Process.wait2(pid)
    $child_pids.delete(pid) # rubocop:disable Style/GlobalVars

    status.exited? ? status.success? : nil
  rescue SystemCallError
    nil
  end

  def perform!(cmd, output_mode: nil, sensitive_data_pattern: nil)
    success = perform(cmd, output_mode: output_mode, sensitive_data_pattern: sensitive_data_pattern)
    success || Shell.abort("Command exited with non-zero status.")
  end

  def perform_yaml(cmd)
    Shell.debug("CMD", cmd)

    result = Shell.cmd(cmd)
    YAML.safe_load(result[:output], permitted_classes: [Time]) if result[:success]
  end

  def perform_yaml!(cmd)
    perform_yaml(cmd) || Shell.abort("Command exited with non-zero status.")
  end

  def gvc_org
    "--gvc #{gvc} --org #{org}"
  end
end
