# Changelog

All notable changes to this project's source code will be documented in this file. Items under `Unreleased` are upcoming features that will be out in the next version.

## Contributors

Please follow the recommendations outlined at [keepachangelog.com](https://keepachangelog.com). Please use the existing headings and styling as a guide, and add a link for the version diff at the bottom of the file. Also, please update the `Unreleased` link to compare it to the latest release version.

In addition to the standard keepachangelog.com categories, this project uses a local `### Breaking Changes` heading at the top of each version section to surface backwards-incompatible changes. The release tooling treats that heading as a signal to require a major version bump (see `expected_bump_type_from_changelog_section` in `rakelib/create_release.rake`).

## Versions

## [Unreleased]

### Added

- **Added `--mode=stop` to `cleanup-stale-apps` for reversible idle-app handling.** Suspends all workloads via `cpflow ps:stop` instead of deleting; restore with `cpflow ps:start`. Default `--mode=delete` preserves existing behavior. [Issue 295](https://github.com/shakacode/control-plane-flow/issues/295).

### Fixed

- Fixed `cpflow run` interactive sessions printing a confusing "Command exited with non-zero status" error when `cpln workload exec` exits non-zero or is signal-killed on session close. cpflow now prints an actionable `cpflow ps:stop` hint instead; exit code 64 is returned for non-zero exits and 130 for signal termination so scripted callers can still detect failure. Fixes [issue 199](https://github.com/shakacode/control-plane-flow/issues/199). [PR 301](https://github.com/shakacode/control-plane-flow/pull/301) by [Justin Gordon](https://github.com/justin808).
- Fixed `deploy-image` showing container names instead of workload names in the "Deploying image..." steps and the "Deployed endpoints" summary when a workload's name differs from its container's name. Also guards against duplicate work per workload by deploying only the first container whose image matches the app-image pattern; workloads are expected to run a single app-image container, so any additional matches are skipped. Fixes [issue 255](https://github.com/shakacode/control-plane-flow/issues/255). [PR 294](https://github.com/shakacode/control-plane-flow/pull/294) by [Justin Gordon](https://github.com/justin808).

## [5.0.0.rc.2] - 2026-05-23

### Added

- **Generated local helpers for downstream GitHub Actions ref pinning and validation.** `cpflow generate-github-actions` now writes `bin/pin-cpflow-github-ref` and `bin/test-cpflow-github-flow` so downstream repos can safely pin wrappers to release tags or full upstream commit SHAs, validate wrapper ref consistency, and test unreleased upstream workflow changes without using moving branch refs. [PR 308](https://github.com/shakacode/control-plane-flow/pull/308) by [Justin Gordon](https://github.com/justin808).

### Changed

- **Documented the downstream testing and release model for reusable GitHub Actions.** The CI automation docs now spell out what is tied to the upstream GitHub ref, what is tied to the RubyGems version, how `CPFLOW_VERSION` changes runtime installation, and how to test an unmerged upstream PR from a downstream app. [PR 308](https://github.com/shakacode/control-plane-flow/pull/308) by [Justin Gordon](https://github.com/justin808).
- **Updated generated GitHub Actions workflow templates to Node 24-compatible action versions** by using `actions/checkout@v6` and `actions/github-script@v8`. [PR 303](https://github.com/shakacode/control-plane-flow/pull/303) by [Justin Gordon](https://github.com/justin808).

### Fixed

- **Relaxed `thor` runtime dependency from `~> 1.4` to `~> 1.3`** so cpflow can be bundled into Rails 8 apps that pull in `solid_queue` 1.1.0 (Rails 8.0.x default), which pins `thor ~> 1.3.1`. The previous `~> 1.4` constraint had zero overlap with that pin and forced users to install cpflow globally instead of adding it to the Gemfile. [Issue 264](https://github.com/shakacode/control-plane-flow/issues/264) / [PR 291](https://github.com/shakacode/control-plane-flow/pull/291) by [Justin Gordon](https://github.com/justin808).

## [5.0.0.rc.1] - 2026-05-11

### Breaking Changes

- BREAKING CHANGE: Bumped minimum Ruby version from 2.7.0 to 3.0.0. Users still on Ruby 2.7 must upgrade to Ruby 3.0 or newer before installing cpflow 5.x. [PR 258](https://github.com/shakacode/control-plane-flow/pull/258) by [Justin Gordon](https://github.com/justin808).
- BREAKING CHANGE: `cpflow exists` now returns exit code 3 when the app is not found, preserving 64 for real errors so scripts can distinguish not-found from API/auth failures. Affected callers: only scripts that branched specifically on `[ $? -eq 64 ]` as a "not found" signal — those will now misroute "not found" into the error branch and must switch to checking for exit 3. Scripts that treat any non-zero exit as "not found" are unaffected. The change is isolated to `lib/command/exists.rb` and `lib/constants/exit_code.rb` (`NOT_FOUND = 3`), so users hitting a regression can bisect by file. [PR 278](https://github.com/shakacode/control-plane-flow/pull/278) by [Justin Gordon](https://github.com/justin808).
- BREAKING CHANGE: `cpflow generate` now writes `bundle config set with 'production'` in the generated Dockerfile, dropping the previous `'staging production'` group set. Apps that placed gems specifically under a `staging:` group in their `Gemfile` (e.g. APM agents, observability libraries that should ship to staging) must move those gems into the `production:` group before regenerating, or the regenerated Dockerfile will exclude them at install time. New scaffolds are unaffected. [PR 278](https://github.com/shakacode/control-plane-flow/pull/278) by [Justin Gordon](https://github.com/justin808).

### Added

- **Added the GitHub Actions flow generator and readiness checks for staging, review-app, and production-promotion workflows.** [PR 278](https://github.com/shakacode/control-plane-flow/pull/278) by [Justin Gordon](https://github.com/justin808).
- **Added `use-digest-image-ref` (also configurable through `use_digest_image_ref` in `controlplane.yml`) option to `deploy-image` and `promote-app-from-upstream` commands.** [PR 249](https://github.com/shakacode/control-plane-flow/pull/249) by [Zakir Dzhamaliddinov](https://github.com/zzaakiirr).

### Changed

- **Renamed the generated review-app PR comment commands to a namespaced `+review-app-*` family.** [PR 285](https://github.com/shakacode/control-plane-flow/pull/285) by [Justin Gordon](https://github.com/justin808). `/deploy-review-app` → `+review-app-deploy`, `/delete-review-app` → `+review-app-delete`, and `/help` → `+review-app-help`. The `+` prefix avoids collision with GitHub's reserved slash-command surface and makes the three commands obviously part of one namespaced family. Repos that ran `cpflow generate-github-actions` against 5.0.0.rc.0 must regenerate the generated `.github/workflows/cpflow-*.yml` files and `.github/cpflow-help.md`, then update saved instructions or runbooks.
- **Updated runtime dependencies: `dotenv` (~> 2.8.1 → ~> 3.1), `jwt` (~> 2.8.1 → ~> 3.1), `psych` (~> 5.1.0 → ~> 5.2), and `thor` (~> 1.2.1 → ~> 1.4).** [PR 258](https://github.com/shakacode/control-plane-flow/pull/258) by [Justin Gordon](https://github.com/justin808).

## [4.2.0] - 2026-02-19

### Added

- Suppress Node.js deprecation warnings from internal `cpln` calls by setting `NODE_NO_WARNINGS=1`, producing cleaner cpflow output. [PR 256](https://github.com/shakacode/control-plane-flow/pull/256) by [Judah Meek](https://github.com/Judahmeek).

### Fixed

- Fixed issue where `run` command could hang indefinitely when updating runner workload. [PR 260](https://github.com/shakacode/control-plane-flow/pull/260) by [Sergey Tarasov](https://github.com/dzirtusss).

### Security

- Redact sensitive data (Authorization headers, tokens) from `--trace` output. [PR 261](https://github.com/shakacode/control-plane-flow/pull/261) by [Sergey Tarasov](https://github.com/dzirtusss).

## [4.1.1] - 2025-03-14


### Fixed

- Fixed issue where `ps`, `ps:start`, `ps:stop`, `ps:wait`, and `run` commands fail when trying to fetch replicas with CPLN CLI. [PR 254](https://github.com/shakacode/control-plane-flow/pull/254) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [4.1.0] - 2024-12-17

### Fixed

- Fixed issue where `run` command fails when runner workload has ENV but original workload does not. [PR 227](https://github.com/shakacode/control-plane-flow/pull/227) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed potential infinite loop that could occur for a command if one of the execution steps fails and gets stuck. [PR 217](https://github.com/shakacode/control-plane-flow/pull/217) by [Zakir Dzhamaliddinov](https://github.com/zzaakiirr).
- Fixed issue where app cannot be deleted because one of the workloads has a volumeset in-use. [PR 245](https://github.com/shakacode/control-plane-flow/pull/245) by [Zakir Dzhamaliddinov](https://github.com/zzaakiirr).
- Fixed `resolv` may be not properly required [PR 250](https://github.com/shakacode/control-plane-flow/pull/250) by [Sergey Tarasov](https://github.com/dzirtusss).

### Added

- Added `--docker-context` option to `build-image` command. [PR 250](https://github.com/shakacode/control-plane-flow/pull/250) by [Sergey Tarasov](https://github.com/dzirtusss).


## [4.0.0] - 2024-08-21

### Fixed

- Fixed issue where common options are not forwarded to other commands. [PR 207](https://github.com/shakacode/control-plane-flow/pull/207) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed BYOK endpoint. [PR 209](https://github.com/shakacode/control-plane-flow/pull/209) by [Sergey Tarasov](https://github.com/dzirtusss).
- Fixed issue where `generate` command fails if no project config exists. [PR 219](https://github.com/shakacode/control-plane-flow/pull/219) by [Zakir Dzhamaliddinov](https://github.com/zzaakiirr).
- Bumped min `cpln` version to `3.1.0` and fixed `cpln workload exec` calls. [PR 226](https://github.com/shakacode/control-plane-flow/pull/226) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [3.0.1] - 2024-06-26

### Fixed

- Moved development dependencies to Gemfile and updated many of them. [PR 208](https://github.com/shakacode/control-plane-flow/pull/208) by [Justin Gordon](https://github.com/justin808).

## [3.0.0] - 2024-06-21

First release of `cpflow`.

## [2.2.4] - 2024-06-21

Deprecated `cpl` gem. New gem is `cpflow`.

## [2.2.1] - 2024-06-17

### Fixed

- Fixed issue where latest image may be incorrect. [PR 201](https://github.com/shakacode/control-plane-flow/pull/201) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed issue where `build-image` command hangs forever waiting for image to be available. [PR 201](https://github.com/shakacode/control-plane-flow/pull/201) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [2.2.0] - 2024-06-07

### Fixed

- Fixed issue where `ps:wait` command hangs forever if workloads are suspended. [PR 198](https://github.com/shakacode/control-plane-flow/pull/198) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Added

- Added a timeout for `run` jobs (6 hours by default, but configurable through `runner_job_timeout` in `controlplane.yml`). [PR 194](https://github.com/shakacode/control-plane-flow/pull/194) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Changed

- `run` command now overrides the `--image`, `--cpu`, and `--memory` for each job separately, which completely removes any race conditions when running simultaneous jobs with different overrides. [PR 182](https://github.com/shakacode/control-plane-flow/pull/182) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `run` jobs now use a CPU size of 1 (1 core) and a memory size of 2Gi (2 gibibytes) by default (configurable through `runner_job_default_cpu` and `runner_job_default_memory` in `controlplane.yml`). [PR 182](https://github.com/shakacode/control-plane-flow/pull/182) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `run` command now keeps ENV values synced between original and runner workloads. [PR 196](https://github.com/shakacode/control-plane-flow/pull/196) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [2.1.0] - 2024-05-27

### Fixed

- Fixed issue where release script was not running from the app image. [PR 183](https://github.com/shakacode/control-plane-flow/pull/183) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed issue where deprecated options were not being warned. [PR 183](https://github.com/shakacode/control-plane-flow/pull/183) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Added

- Added post-creation hook to `setup-app` command (configurable through `hooks.post_creation` in `controlplane.yml`). [PR 183](https://github.com/shakacode/control-plane-flow/pull/183) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added pre-deletion hook to `delete` command (configurable through `hooks.pre_deletion` in `controlplane.yml`). [PR 183](https://github.com/shakacode/control-plane-flow/pull/183) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added `doctor` command to run validations. [PR 185](https://github.com/shakacode/control-plane-flow/pull/185) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Changed

- `cpflow` now sets `CPLN_SKIP_UPDATE_CHECK` to `true` for all internal `cpln` calls, which disables the version check and prevents cluttering the logs. [PR 180](https://github.com/shakacode/control-plane-flow/pull/180) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `setup-app` command now automatically creates a secret, policy, and identity for the app if they do not exist. The `--skip-secrets-setup` option prevents this behavior. [PR 181](https://github.com/shakacode/control-plane-flow/pull/181) by [Rafael Gomes](https://github.com/rafaelgomesxyz). [PR 190](https://github.com/shakacode/control-plane-flow/pull/190) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Specific validations are now run before commands, and the command will exit with a non-zero code if any validation fails. Can be disabled by setting `DISABLE_VALIDATIONS` env var to `true`. [PR 185](https://github.com/shakacode/control-plane-flow/pull/185) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Deprecated the `--skip-secret-access-binding` option in favor of `--skip-secrets-setup`. This can also now be configured through `skip_secrets_setup` in `controlplane.yml` [PR 190](https://github.com/shakacode/control-plane-flow/pull/190) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [2.0.2] - 2024-05-18

- Fixed issue with improper handling of job statuses. Fixed issue with interactive magic string showing and exit code. [PR 177](https://github.com/shakacode/control-plane-flow/pull/177) by [Sergey Tarasov](https://github.com/dzirtusss).

## [2.0.1] - 2024-05-16

### Fixed

- Fixed issue where `cleanup-stale-apps` command fails to delete apps with volumesets. [PR 175](https://github.com/shakacode/control-plane-flow/pull/175) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [2.0.0] - 2024-05-15

### BREAKING CHANGES

- Commands that finished with a failure now exit with code `64` instead of `1`. [PR 132](https://github.com/shakacode/control-plane-flow/pull/132) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Bumped minimum `cpln` version to `2.0.1` (`cpln workload cron get` is required). [PR 171](https://github.com/shakacode/control-plane-flow/pull/171) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `run:cleanup` command has been removed. [PR 151](https://github.com/shakacode/control-plane-flow/pull/151) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `deploy-image` command now runs the release script in the context of the `run` command. [PR 151](https://github.com/shakacode/control-plane-flow/pull/151) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Fixed

- Fixed race conditions when using latest image in `run` command. [PR 163](https://github.com/shakacode/control-plane-flow/pull/163) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Added

- Added options to `run` command to override the workload container's `--cpu`, `--memory`, and `--entrypoint`. [PR 151](https://github.com/shakacode/control-plane-flow/pull/151) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added `--workload` option to `delete` command to delete a specific workload. [PR 151](https://github.com/shakacode/control-plane-flow/pull/151) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added `--replica` option to `logs` command to see logs from a specific replica. [PR 151](https://github.com/shakacode/control-plane-flow/pull/151) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added `--replica` option to `ps:stop` command to stop a specific replica. [PR 151](https://github.com/shakacode/control-plane-flow/pull/151) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added option to set custom names for secrets and secrets policy, using `secrets_name` and `secrets_policy_name` in `controlplane.yml`. [PR 159](https://github.com/shakacode/control-plane-flow/pull/159) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Changed

- An error is now raised if the org does not exist. [PR 167](https://github.com/shakacode/control-plane-flow/pull/167) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Common options are now shown in help. [PR 169](https://github.com/shakacode/control-plane-flow/pull/169) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `run` command now uses a single reusable cron workload and works for both interactive and non-interactive jobs. [PR 151](https://github.com/shakacode/control-plane-flow/pull/151) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `run:detached` command has been deprecated in favor of `run`. [PR 151](https://github.com/shakacode/control-plane-flow/pull/151) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `deploy-image` command now raises an error if image does not exist. [PR 153](https://github.com/shakacode/control-plane-flow/pull/153) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `delete` command now unbinds identity from policy (if bound) when deleting app. [PR 170](https://github.com/shakacode/control-plane-flow/pull/170) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.4.0] - 2024-03-21

### Added

- Added new template substitution variables (used by `apply-template` and `setup-app` commands): `{{APP_LOCATION_LINK}}`, `{{APP_IMAGE_LINK}}`, `{{APP_IDENTITY}}`, `{{APP_IDENTITY_LINK}}`, `{{APP_SECRETS}}` and `{{APP_SECRETS_POLICY}}`. [PR 146](https://github.com/shakacode/control-plane-flow/pull/146) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added `--run-release-phase` option to `deploy-image` command to run release script before deploying (same step as in `promote-app-from-upstream` command). [PR 146](https://github.com/shakacode/control-plane-flow/pull/146) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Changed

- Template substitution (used by `apply-template` and `setup-app` commands) now uses double braces (e.g., `APP_ORG` -> `{{APP_ORG}}`). This change is backwards compatible. [PR 146](https://github.com/shakacode/control-plane-flow/pull/146) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Renamed template substitution variable `APP_GVC` to `{{APP_NAME}}` (used by `apply-template` and `setup-app` commands). This change is backwards compatible. [PR 146](https://github.com/shakacode/control-plane-flow/pull/146) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `setup-app` command now automatically binds the app to the secrets policy, as long as both the identity and the policy exist. Added `--skip-secret-access-binding` option to prevent this behavior. [PR 146](https://github.com/shakacode/control-plane-flow/pull/146) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Local API token is now refreshed when it is about to expire. [PR 146](https://github.com/shakacode/control-plane-flow/pull/146) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `apply-template` command now exits with non-zero code if failed to apply any templates. [PR 146](https://github.com/shakacode/control-plane-flow/pull/146) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.3.0] - 2024-03-19

### Fixed

- Fixed issue where cpln profile was not switched back to `default` if an error happened while running `copy-image-from-upstream` command. [PR 135](https://github.com/shakacode/control-plane-flow/pull/135) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed issue that didn't allow using upstream with `match_if_app_name_starts_with` set to `true` in `copy-image-from-upstream` command. [PR 136](https://github.com/shakacode/control-plane-flow/pull/136) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Added

- Added `--no-clean-on-failure` option to `run:detached` command to skip deletion of failed workload run. [PR 133](https://github.com/shakacode/control-plane-flow/pull/133) by [Justin Gordon](https://github.com/justin808) and [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added `--domain` option to `maintenance`, `maintenance:on` and `maintenance:off` commands. [PR 131](https://github.com/shakacode/control-plane-flow/pull/131) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added `default_domain` config to specify domain for `maintenance`, `maintenance:on` and `maintenance:off` commands. [PR 131](https://github.com/shakacode/control-plane-flow/pull/131) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added option to specify upstream for `copy-image-from-upstream` command through `CPLN_UPSTREAM` env var. [PR 138](https://github.com/shakacode/control-plane-flow/pull/138) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Changed

- `build-image` command now accepts extra options and passes them to `docker build`. [PR 126](https://github.com/shakacode/control-plane-flow/pull/126) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `CPLN_ORG_UPSTREAM` env var now takes precedence over config from `controlplane.yml` in `copy-image-from-upstream` command. [PR 137](https://github.com/shakacode/control-plane-flow/pull/137) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `info` command now works properly for apps with `match_if_app_name_starts_with` set to `true`.[PR 139](https://github.com/shakacode/control-plane-flow/pull/139) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `info` command now lists workloads in the same order as `controlplane.yml`. [PR 139](https://github.com/shakacode/control-plane-flow/pull/139) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Improved domain workload matching for `maintenance`, `maintenance:on` and `maintenance:off` commands (instead of matching only by workload, it now matches by org + app + workload, which is more accurate). [PR 140](https://github.com/shakacode/control-plane-flow/pull/140) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.2.0] - 2024-01-04

### Fixed

- Fixed issue where `info` command does not respect `CPLN_ORG` env var. [PR 88](https://github.com/shakacode/control-plane-flow/pull/88) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed issues with running `cpflow --version` and `cpflow --help` where no configuration file exists. [PR 109](https://github.com/shakacode/control-plane-flow/pull/109) by [Mostafa Ahangarha](https://github.com/ahangarha).
- Fixed issue where `delete` command fails to delete apps with volumesets. [PR 123](https://github.com/shakacode/control-plane-flow/pull/123) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Added

- Added `--org` option to all commands. [PR 88](https://github.com/shakacode/control-plane-flow/pull/88) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added option to set the app with a `CPLN_APP` env var. [PR 88](https://github.com/shakacode/control-plane-flow/pull/88) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Show `org` and `app` on every command excluding `info`, `version`, `maintenance`, `env`, `ps`, and `latest_image`. [PR 94](https://github.com/shakacode/control-plane-flow/pull/94) by [Mostafa Ahangarha](https://github.com/ahangarha).
- Added option to only use `CPLN_ORG` and `CPLN_APP` env vars if `allow_org_override_by_env` and `allow_app_override_by_env` configs are set to `true` in `controlplane.yml`. [PR 109](https://github.com/shakacode/control-plane-flow/pull/109) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added `CPLN_LOCATION` env variable and `--location` option for `apply-template`, `ps`, `run`, `run:detached`. [PR 105](https://github.com/shakacode/control-plane-flow/pull/105) by [Mostafa Ahangarha](https://github.com/ahangarha).
- Added `generate` command for creating basic Control Plane configuration directory. [PR 116](https://github.com/shakacode/control-plane-flow/pull/116) by [Mostafa Ahangarhga](https://github.com/ahangarha).
- Added `--trace` option to all commands for more detailed logs. [PR 124](https://github.com/shakacode/control-plane-flow/pull/124) by [Justin Gordon](https://github.com/justin808).
- Added better error message to check the org name in case of a 403 error. [PR 124](https://github.com/shakacode/control-plane-flow/pull/124) by [Justin Gordon](https://github.com/justin808).

### Changed

- `--org` option now takes precedence over `CPLN_ORG` env var, which takes precedence over `cpln_org` from `controlplane.yml`. [PR 88](https://github.com/shakacode/control-plane-flow/pull/88) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Renamed `setup` config into `setup_app_templates`. [PR 112](https://github.com/shakacode/control-plane-flow/pull/112) by [Mostafa Ahangarha](https://github.com/ahangarha).

## [1.1.2] - 2023-10-25

### Fixed

- Fixed failed build on MacOS by adding platform flag and fixed multiple files in yaml document for template. [PR 81](https://github.com/shakacode/control-plane-flow/pull/81) by [Justin Gordon](https://github.com/justin808).

### Added

- Added `open-console` command to open the app console on Control Plane. [PR 83](https://github.com/shakacode/control-plane-flow/pull/83) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added option to set the org with a `CPLN_ORG`/`CPLN_ORG_UPSTREAM` env var. [PR 83](https://github.com/shakacode/control-plane-flow/pull/83) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added `--verbose` option to all commands for more detailed logs. [PR 83](https://github.com/shakacode/control-plane-flow/pull/83) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Changed

- Calling `cpflow` with no command now shows the help menu. [PR 83](https://github.com/shakacode/control-plane-flow/pull/83) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.1.1] - 2023-09-21

### Fixed

- Fixed issue where API token is not reset when switching profile. [PR 77](https://github.com/shakacode/control-plane-flow/pull/77) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.1.0] - 2023-09-20

### Fixed

- Fixed issue where `copy-image-from-upstream` command does not copy commit. [PR 70](https://github.com/shakacode/control-plane-flow/pull/70) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed issue where an error is not raised if the app is not defined. [PR 73](https://github.com/shakacode/control-plane-flow/pull/73) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed issue where `CPLN_ENDPOINT` is not used if available. [PR 75](https://github.com/shakacode/control-plane-flow/pull/75) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Added

- Added `image_retention_max_qty` config to clean up images based on max quantity with `cleanup-images` command. [PR 72](https://github.com/shakacode/control-plane-flow/pull/72) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Changed

- Updated docs for `run` commands regarding passing arguments at the end. [PR 71](https://github.com/shakacode/control-plane-flow/pull/71) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Renamed `cleanup-old-images` command to `cleanup-images`. [PR 72](https://github.com/shakacode/control-plane-flow/pull/72) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Renamed `old_image_retention_days` config to `image_retention_days`. [PR 72](https://github.com/shakacode/control-plane-flow/pull/72) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.0.4] - 2023-07-24

### Fixed

- Fixed issue where `run` commands fail when not providing image. [PR 68](https://github.com/shakacode/control-plane-flow/pull/68) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.0.3] - 2023-07-07

### Fixed

- Fixed `run` commands when specifying image. [PR 62](https://github.com/shakacode/control-plane-flow/pull/62) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed `run:cleanup` command for non-interactive workloads. [PR 63](https://github.com/shakacode/control-plane-flow/pull/63) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed `run:cleanup` command for all apps that start with name. [PR 64](https://github.com/shakacode/control-plane-flow/pull/64) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed `cleanup-old-images` command for all apps that start with name. [PR 65](https://github.com/shakacode/control-plane-flow/pull/65) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed `--help` option. [PR 66](https://github.com/shakacode/control-plane-flow/pull/66) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Added

- Added `--use-local-token` option to `run:detached` command. [PR 61](https://github.com/shakacode/control-plane-flow/pull/61) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.0.2] - 2023-07-02

### Added

- Added steps to migrate to docs. [PR 57](https://github.com/shakacode/control-plane-flow/pull/57) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added `ps:wait` command. [PR 58](https://github.com/shakacode/control-plane-flow/pull/58) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.0.1] - 2023-06-28

### Fixed

- Fixed `cleanup-stale-apps` command when app does not have image. [PR 55](https://github.com/shakacode/control-plane-flow/pull/55) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Changed

- Improved docs. [PR 50](https://github.com/shakacode/control-plane-flow/pull/50) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.0.0] - 2023-05-29

First release.

[Unreleased]: https://github.com/shakacode/control-plane-flow/compare/v5.0.0.rc.2...HEAD
[5.0.0.rc.2]: https://github.com/shakacode/control-plane-flow/compare/v5.0.0.rc.1...v5.0.0.rc.2
[5.0.0.rc.1]: https://github.com/shakacode/control-plane-flow/compare/v4.2.0...v5.0.0.rc.1
[4.2.0]: https://github.com/shakacode/control-plane-flow/compare/v4.1.1...v4.2.0
[4.1.1]: https://github.com/shakacode/control-plane-flow/compare/v4.1.0...v4.1.1
[4.1.0]: https://github.com/shakacode/control-plane-flow/compare/v4.0.0...v4.1.0
[4.0.0]: https://github.com/shakacode/control-plane-flow/compare/v3.0.1...v4.0.0
[3.0.1]: https://github.com/shakacode/control-plane-flow/compare/v3.0.0...v3.0.1
[3.0.0]: https://github.com/shakacode/control-plane-flow/compare/v2.2.4...v3.0.0
[2.2.4]: https://github.com/shakacode/control-plane-flow/compare/v2.2.1...v2.2.4
[2.2.1]: https://github.com/shakacode/control-plane-flow/compare/v2.2.0...v2.2.1
[2.2.0]: https://github.com/shakacode/control-plane-flow/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/shakacode/control-plane-flow/compare/v2.0.2...v2.1.0
[2.0.2]: https://github.com/shakacode/control-plane-flow/compare/v2.0.1...v2.0.2
[2.0.1]: https://github.com/shakacode/control-plane-flow/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/shakacode/control-plane-flow/compare/v1.4.0...v2.0.0
[1.4.0]: https://github.com/shakacode/control-plane-flow/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/shakacode/control-plane-flow/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/shakacode/control-plane-flow/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/shakacode/control-plane-flow/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/shakacode/control-plane-flow/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/shakacode/control-plane-flow/compare/v1.0.4...v1.1.0
[1.0.4]: https://github.com/shakacode/control-plane-flow/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/shakacode/control-plane-flow/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/shakacode/control-plane-flow/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/shakacode/control-plane-flow/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/shakacode/control-plane-flow/releases/tag/v1.0.0
