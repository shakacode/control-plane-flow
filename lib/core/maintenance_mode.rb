# frozen_string_literal: true

class MaintenanceMode
  extend Forwardable

  DOMAIN_WORKLOAD_UPDATE_MAX_RETRY_COUNT = 30
  DOMAIN_WORKLOAD_UPDATE_RETRY_WAIT = 1
  DOMAIN_WORKLOAD_UPDATE_STEP_OPTIONS = {
    retry_on_failure: true,
    max_retry_count: DOMAIN_WORKLOAD_UPDATE_MAX_RETRY_COUNT,
    wait: DOMAIN_WORKLOAD_UPDATE_RETRY_WAIT
  }.freeze

  def_delegators :@command, :config, :progress, :cp, :step, :run_cpflow_command

  def initialize(command)
    @command = command
  end

  def enabled?
    validate_domain_exists!
    cp.domain_workload_matches?(domain_data, maintenance_workload)
  end

  def disabled?
    validate_domain_exists!
    cp.domain_workload_matches?(domain_data, one_off_workload)
  end

  def enable!
    if enabled?
      progress.puts("Maintenance mode is already enabled for app '#{config.app}'.")
    else
      enable_maintenance_mode
    end
  end

  def disable!
    if disabled?
      progress.puts("Maintenance mode is already disabled for app '#{config.app}'.")
    else
      disable_maintenance_mode
    end
  end

  private

  def enable_maintenance_mode
    validate_maintenance_workload_exists!

    start_or_stop_maintenance_workload(:start)
    switch_domain_workload(to: maintenance_workload)
    start_or_stop_all_workloads(:stop)

    progress.puts("\nMaintenance mode enabled for app '#{config.app}'.")
  end

  def disable_maintenance_mode
    validate_maintenance_workload_exists!

    start_or_stop_maintenance_workload(:start)
    switch_domain_workload(to: one_off_workload)
    start_or_stop_all_workloads(:stop)

    progress.puts("\nMaintenance mode disabled for app '#{config.app}'.")
  end

  def validate_domain_exists!
    return if domain_data

    raise "Can't find domain. " \
          "Maintenance mode is only supported for domains that use path based routing mode " \
          "and have a route configured for the prefix '/' on either port 80 or 443."
  end

  def validate_maintenance_workload_exists!
    cp.fetch_workload!(maintenance_workload)
  end

  def start_or_stop_all_workloads(action)
    run_cpflow_command("ps:#{action}", "-a", config.app, "--wait")

    progress.puts
  end

  def start_or_stop_maintenance_workload(action)
    run_cpflow_command("ps:#{action}", "-a", config.app, "-w", maintenance_workload, "--wait")

    progress.puts
  end

  def switch_domain_workload(to:)
    domain_name = domain_data["name"]

    step("Requesting workload switch for domain '#{domain_name}' to '#{to}'") do
      request_domain_workload_update(to)
    end

    step("Waiting for domain '#{domain_name}' workload to switch to '#{to}'", **DOMAIN_WORKLOAD_UPDATE_STEP_OPTIONS) do
      refreshed_domain_data = refresh_domain_data(domain_name)
      refreshed_domain_data && cp.domain_workload_matches?(refreshed_domain_data, to)
    end

    progress.puts
  end

  def request_domain_workload_update(workload)
    cp.set_domain_workload(domain_data, workload)
  end

  def refresh_domain_data(domain_name)
    cp.fetch_domain(domain_name).tap do |refreshed_domain_data|
      @domain_data = refreshed_domain_data if refreshed_domain_data
    end
  end

  def domain_data
    @domain_data ||=
      if config.domain
        cp.fetch_domain(config.domain)
      else
        cp.find_domain_for([one_off_workload, maintenance_workload])
      end
  end

  def one_off_workload
    @one_off_workload ||= config[:one_off_workload]
  end

  def maintenance_workload
    @maintenance_workload ||= config.current[:maintenance_workload] || "maintenance"
  end
end
