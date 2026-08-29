# frozen_string_literal: true

require "time"

require_relative "command_helpers"

# Defensive garbage collection for CI fixtures that a previous run left behind.
#
# `after(:suite)` deletes everything a run created, including when examples
# fail, but it never executes when the process itself dies: a canceled GitHub
# Actions job, a runner timeout, a `SIGKILL`. Those runs leak `dummy-test-*`
# GVCs that nothing ever reclaims, and enough leaks exhaust the org's GVC quota
# and block every later run with `Quota <gvcs> has been maxed out`.
#
# This sweep runs from `before(:suite)`, not `after(:suite)`: quota has to be
# freed before the current run provisions its own fixtures, and running before
# anything is created is also what makes it impossible to delete a fixture of
# the run performing the sweep.
#
# Safety boundary, all of which must hold before anything is deleted:
#
# 1. Org — only `CommandHelpers.dummy_test_org`, the org this suite is already
#    creating and deleting `dummy-test-*` apps in on every run. The org is not a
#    parameter, so no caller can point the sweep somewhere else.
# 2. Name — only names matching `CommandHelpers::DUMMY_TEST_APP_NAME_PATTERN`,
#    anchored at both ends, so permanent fixtures such as `dummy-test-upstream`
#    and any non-test app are never candidates.
# 3. Run — never a name carrying this run's own global identifier.
# 4. Age — never a GVC younger than `MIN_AGE_SECONDS` (see below).
# 5. Evidence — a GVC whose creation time is missing or unparseable is kept.
#    The sweep only deletes what it positively identified as stale; it never
#    guesses, and a failed list call skips the sweep entirely.
#
# A sweep failure is reported and swallowed. This is hygiene, not an assertion,
# and it must never turn a green suite red.
module StaleDummyAppSweeper
  module_function

  # A GitHub-hosted job is hard-killed at six hours, so a fixture belonging to a
  # concurrent in-flight run can never be older than that. Requiring twice that
  # ceiling leaves a full six hours of margin for clock skew between the API's
  # `created` timestamp and the runner, and for longer self-hosted or local runs.
  # Leaked GVCs survive for weeks, so recovering them a few hours later costs
  # nothing; deleting a live run's GVC would break that run.
  MIN_AGE_SECONDS = 12 * 60 * 60

  def sweep(api: ControlplaneApi.new, now: Time.now.utc, output: $stdout)
    org = CommandHelpers.dummy_test_org
    output.puts("\nSweeping stale '#{CommandHelpers::DUMMY_TEST_APP_PREFIX}' apps older than " \
                "#{MIN_AGE_SECONDS / 3600} hours in org '#{org}'")

    fixtures = fixture_gvcs(api, org, output)
    fixtures&.each { |gvc| sweep_gvc(api, org, gvc, now, output) }
    output.puts
  end

  # Returns the GVCs inside the naming boundary, or `nil` when the org cannot be
  # listed. Without the list nothing has been positively identified as stale, so
  # the caller deletes nothing.
  def fixture_gvcs(api, org, output)
    gvcs = api.gvc_list(org: org)["items"]
    fixtures = gvcs.select { |gvc| CommandHelpers::DUMMY_TEST_APP_NAME_PATTERN.match?(gvc["name"].to_s) }
    output.puts("  Found #{fixtures.length} test fixture(s), ignoring #{gvcs.length - fixtures.length} other GVC(s)")

    fixtures
  rescue StandardError => e
    output.puts("  Skipped the sweep: could not list GVCs in org '#{org}' (#{e.class}: #{e.message})")

    nil
  end

  def sweep_gvc(api, org, gvc, now, output)
    name = gvc["name"]
    reason = keep_reason(gvc, now)
    return output.puts("  Keeping '#{name}': #{reason}") if reason

    return unless delete_volumesets(api, org, name, output)

    api.gvc_delete(org: org, gvc: name)
    output.puts("  Deleted stale app '#{name}'")
  rescue StandardError => e
    output.puts("  Failed to delete stale app '#{gvc['name']}' (#{e.class}: #{e.message})")
  end

  # `Command::Delete` removes volumesets, and the workloads attached to them, before
  # deleting the GVC (`delete_volumesets` then `delete_gvc`). A bare `gvc_delete` does
  # not cascade to them, so a fixture carrying a volumeset -- the Postgres templates do
  # -- would fail to delete or strand the volumeset. Mirror that order here.
  #
  # Returns false when cleanup failed, so the GVC is left for a later run rather than
  # half-deleted.
  def delete_volumesets(api, org, name, output)
    volumesets = api.list_volumesets(org: org, gvc: name)["items"] || []
    volumesets.each { |volumeset| delete_volumeset(api, org, name, volumeset, output) }

    true
  rescue StandardError => e
    output.puts("  Keeping '#{name}': could not clear its volumesets (#{e.class}: #{e.message})")
    false
  end

  def delete_volumeset(api, org, name, volumeset, output)
    workloads = volumeset.dig("status", "workloadLinks")&.map { |link| link.split("/").last }
    workloads&.each { |workload| api.delete_workload(org: org, gvc: name, workload: workload) }
    api.delete_volumeset(org: org, gvc: name, volumeset: volumeset["name"])
    output.puts("  Deleted volumeset '#{volumeset['name']}' from stale app '#{name}'")
  end

  # Returns why the GVC must be kept, or `nil` when it is safe to delete.
  def keep_reason(gvc, now)
    return "it belongs to this run" if from_this_run?(gvc["name"])

    age = age_in_seconds(gvc["created"], now)
    return "its creation time is unknown" if age.nil?
    return "it is only #{(age / 60).round} minute(s) old" if age < MIN_AGE_SECONDS

    nil
  end

  def from_this_run?(name)
    name.to_s.include?(CommandHelpers.dummy_test_app_global_identifier)
  end

  def age_in_seconds(created, now)
    created = created.to_s
    return nil if created.empty?

    now - Time.parse(created).utc
  rescue ArgumentError
    nil
  end
end
