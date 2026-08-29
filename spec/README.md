# Running Specs

Some specs exercise only local behavior and can run without Control Plane credentials. This verified offline smoke suite does not contact a Control Plane org:

```sh
CPLN_ORG='' bundle exec rspec \
  spec/patches \
  spec/support_specs \
  spec/core/controlplane_api_direct_spec.rb \
  spec/core/controlplane_api_spec.rb \
  spec/core/doctor_service_spec.rb \
  spec/core/github_flow_readiness/checks_spec.rb \
  spec/core/helpers_spec.rb \
  spec/core/repo_introspection_spec.rb \
  spec/core/shell_spec.rb \
  spec/rakelib/create_release_spec.rb \
  spec/command/no_command_spec.rb \
  spec/command/staging_branch_validation_spec.rb \
  spec/command/test_spec.rb \
  spec/command/update_github_actions_spec.rb \
  spec/command/version_spec.rb \
  spec/command/deploy_image_unit_spec.rb \
  spec/command/promote_app_from_upstream_unit_spec.rb
```

The spec helper still prepares the temporary dummy configuration for these runs. A spec that needs a real Control Plane org raises a clear error when it calls `dummy_test_org`; rerun that spec with `CPLN_ORG` set.

Specs that create, inspect, or delete Control Plane resources need an org with the required access:

```sh
CPLN_ORG=your-org-for-tests bundle exec rspec
```

Slow specs are a subset of the credentialed suite. Run them separately with:

```sh
CPLN_ORG=your-org-for-tests bundle exec rspec --tag slow
```

## Test app cleanup and recovery

Credentialed runs provision `dummy-test-*` apps in `CPLN_ORG`. The org has a GVC
quota (20 in CI), so leaked apps eventually block every later run with
`Quota <gvcs> has been maxed out`.

Two mechanisms keep the org clean.

### Registration for `after(:suite)` cleanup

`run_cpflow_command` and `spawn_cpflow_command` register the app named by `-a`
whenever the command can create one (`setup-app`, `apply-template`), *before*
the command runs. `after(:suite)` then deletes every registered app with
`cpflow delete`, which also removes its volumesets, images, and secret-policy
bindings.

Registering at the command runner rather than in `dummy_test_app` is deliberate:
`dummy_test_app` only builds a name, and builds a fresh random one per example,
so registering there would queue a delete for every name a spec ever mentioned.
Registering before the command runs is what covers the failure paths — a
`setup-app` that creates the GVC and then fails, or an example that fails before
its own `after` hook deletes the app, still leaves the app registered.

Set `SKIP_CLEANUP=true` to keep the apps a run created.

### Stale fixture sweep

`after(:suite)` cannot run when the process itself dies — a canceled GitHub
Actions job, a runner timeout, a `SIGKILL`. `StaleDummyAppSweeper`
(`spec/support/stale_dummy_app_sweeper.rb`) recovers those leaks from
`before(:suite)` of the next credentialed run, so no console cleanup is needed.
It runs before the suite provisions anything, prints every app it deleted and
every app it kept with the reason, and never fails the suite: a sweep failure is
reported and swallowed, because this is hygiene, not an assertion.

The sweep deletes a GVC only when **all** of the following hold:

| Guard | Rule |
| --- | --- |
| Org | Only `CommandHelpers.dummy_test_org` — the org the suite is already creating and deleting `dummy-test-*` apps in on every run. The org is not a parameter, so no caller can point the sweep elsewhere. |
| Name | Only names matching `CommandHelpers::DUMMY_TEST_APP_NAME_PATTERN`, anchored at both ends. Permanent org fixtures whose names merely start with `dummy-test` (such as `dummy-test-upstream`) and any non-test app are never candidates. Never relax this into a `start_with?`/`include?` check. |
| Run | Never a name carrying the current run's global identifier. |
| Age | Never a GVC younger than `MIN_AGE_SECONDS` (12 hours). A GitHub-hosted job is hard-killed at six hours, so a fixture belonging to a concurrent in-flight run can never reach that age. The remaining six hours are margin for clock skew and for longer self-hosted or local runs. Leaked apps survive for weeks, so reclaiming them a few hours later costs nothing, while deleting a live run's app would break that run. |
| Evidence | A GVC with a missing or unparseable creation timestamp is kept, and a failed list call skips the sweep entirely. The sweep only deletes what it positively identified as stale; it never guesses. |

The sweep reclaims the GVC, which is the quota that blocks CI, and with it the
app's workloads and volumesets. Images left behind by an interrupted run are not
swept; they do not consume GVC quota, and the `after(:suite)` path removes them
on any run that exits normally.

`SKIP_CLEANUP=true` disables the sweep as well.

### What the sweep does not reclaim

The sweep deletes a stale fixture's volumesets, their attached workloads, and the
GVC. It deliberately stops there.

`Command::Delete` also unbinds the app identity from its secrets policy before
deleting, and the sweep does not. Doing so needs `config.identity` and
`config.secrets_policy`, which resolve from the app's entry in
`controlplane.yml`; a stale fixture's run identifier is by definition absent from
the current config, so the sweep has no entry to read. Identity bindings are
org-scoped and survive GVC deletion, so a killed run that got as far as
`setup-app`'s identity-binding step can leave one behind. That is a separate
leak from the GVC-quota exhaustion this recovers, and it does not consume GVC
quota. Reclaiming it would mean enumerating and deleting org-level policy
objects, which is a materially wider destructive surface than this sweep takes on.

Org-level images are likewise out of scope: they do not consume GVC quota, and
the `after(:suite)` path removes them on any normally-exiting run.
