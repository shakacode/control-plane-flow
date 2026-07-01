# frozen_string_literal: true

class MaintenanceMode # rubocop:disable Metrics/ClassLength
  extend Forwardable

  DOMAIN_WORKLOAD_UPDATE_MAX_POLL_ATTEMPTS = 30
  DOMAIN_WORKLOAD_UPDATE_RETRY_WAIT_SECONDS = 1
  DOMAIN_WORKLOAD_UPDATE_STEP_OPTIONS = {
    retry_on_failure: true,
    # `with_retry` loops while `retry_count <= max_retry_count` starting from 0, so
    # total attempts == max_retry_count + 1. Subtract 1 so the bounded poll runs
    # exactly DOMAIN_WORKLOAD_UPDATE_MAX_POLL_ATTEMPTS times.
    max_retry_count: DOMAIN_WORKLOAD_UPDATE_MAX_POLL_ATTEMPTS - 1,
    wait: DOMAIN_WORKLOAD_UPDATE_RETRY_WAIT_SECONDS
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
      ensure_app_workloads_stopped
    else
      enable_maintenance_mode
    end
  end

  def disable!
    if disabled?
      progress.puts("Maintenance mode is already disabled for app '#{config.app}'.")
      ensure_maintenance_workload_stopped
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

  # A run that already switched the route but hit the poll timeout aborts before
  # its final workload-stop step runs. The next `enable!`/`disable!` short-circuits
  # on the route check, so do the matching stop here — once the route is on the
  # target, this brings the workloads into the state that route implies. `ps:stop`
  # is idempotent, so each is a no-op once the target workload is already stopped.
  #
  # The stop target differs by direction. `ps:stop -a` covers only
  # `app_workloads` + `additional_workloads`, never the maintenance workload:
  #   - enable!: the route now points at the maintenance workload, so the *app*
  #     workloads are the ones left running and `ps:stop -a` is correct.
  #   - disable!: the route now points at the app workloads (and a short-circuit
  #     `disable!` can run on an app whose app workloads are serving live traffic),
  #     so stopping all workloads would cause an outage. The workload a timed-out
  #     `disable!` leaves running is the maintenance workload, so stop only that.
  def ensure_app_workloads_stopped
    start_or_stop_all_workloads(:stop)
  end

  def ensure_maintenance_workload_stopped
    start_or_stop_maintenance_workload(:stop)
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

    # Unlike the polling step below, the switch request is intentionally not
    # retried: if it fails, nothing has changed yet, so aborting and letting the
    # user re-run is the safe outcome. (Retrying would not help here anyway —
    # `with_retry` retries on a falsy return, and `set_domain_workload` raises
    # rather than returning false.)
    step("Requesting workload switch for domain '#{domain_name}' to '#{to}'") do
      # `set_domain_workload` mutates the route in place, so send a deep copy
      # (round-tripped through JSON, since the domain is plain parsed-API data
      # with string keys and JSON-native values) to keep the cached
      # `@domain_data` reflecting the real server route. The poll re-fetches and
      # matches on that fresh data, but if every poll times out without a routable
      # fetch, `@domain_data` is what a re-run's `enabled?`/`disabled?` check reads
      # — mutating it here would make that check report the requested route, not
      # the actual one.
      domain_data_for_update = JSON.parse(JSON.generate(domain_data))
      cp.set_domain_workload(domain_data_for_update, to)
    end

    wait_for_domain_workload_switch(domain_name, to)

    progress.puts
  end

  # If the route never switches within the bounded poll window, this step aborts
  # (abort_on_error) before any workloads are stopped, so traffic stays on the
  # current workload. The label tells the user how to recover, since an exhausted
  # poll has no error message of its own to print.
  def wait_for_domain_workload_switch(domain_name, to)
    @last_poll_error = nil # reset the poll-error dedup state for this poll window
    step("Waiting for domain '#{domain_name}' workload to switch to '#{to}' " \
         "(re-run this command if it times out)", **DOMAIN_WORKLOAD_UPDATE_STEP_OPTIONS) do
      domain_workload_update_confirmed?(domain_name, to)
    end
  end

  # Refetches the domain, refreshes the cached `@domain_data` when the fetch
  # returns a routable domain, and reports whether the route now points at
  # `workload`. Any error — a 5xx mid-propagation, a transient 403
  # (`ForbiddenError < StandardError`, not a `RuntimeError`), or a network blip —
  # is treated as "not switched yet" so the poll keeps retrying. The broad rescue
  # logs the error to the step's stderr, so a latent bug (e.g. `NoMethodError`)
  # surfaces in the "failed!" output on timeout instead of being swallowed.
  def domain_workload_update_confirmed?(domain_name, workload)
    refreshed_domain_data = cp.fetch_domain(domain_name)
    @domain_data = refreshed_domain_data if refreshed_domain_data
    refreshed_domain_data && cp.domain_workload_matches?(refreshed_domain_data, workload)
  rescue StandardError => e
    # A persistent failure (bad domain name, network outage, a latent bug) repeats
    # the same error on every poll attempt, so only log when the message changes —
    # otherwise the timeout output would carry up to MAX_POLL_ATTEMPTS identical
    # lines. Guard on `tmp_stderr` so this stays safe if ever called outside a
    # `step` block, where no tmp stderr is set up.
    message = "#{e.class}: #{e.message} (#{e.backtrace&.first})\n"
    if message != @last_poll_error && Shell.tmp_stderr
      Shell.write_to_tmp_stderr(message)
      @last_poll_error = message
    end
    false
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
