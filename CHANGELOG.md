# Changelog

All notable changes to this project's source code will be documented in this file. Items under `Unreleased` are upcoming features that will be out in the next version.

## Contributors

Please follow the recommendations outlined at [keepachangelog.com](https://keepachangelog.com). Please use the existing headings and styling as a guide, and add a link for the version diff at the bottom of the file. Also, please update the `Unreleased` link to compare it to the latest release version.

## Versions

## [Unreleased]

Changes since the last non-beta release.

_Please add entries here for your pull requests that are not yet released._

### Fixed

- Fixed app matching when name starts with (the wrong config was being used in some cases - see PR for more details). [PR 150](https://github.com/shakacode/heroku-to-control-plane/pull/150) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.4.0] - 2024-03-20

### Added

- Added new template substitution variables (used by `apply-template` and `setup-app` commands): `{{APP_LOCATION_LINK}}`, `{{APP_IMAGE_LINK}}`, `{{APP_IDENTITY}}`, `{{APP_IDENTITY_LINK}}`, `{{APP_SECRETS}}` and `{{APP_SECRETS_POLICY}}`. [PR 146](https://github.com/shakacode/heroku-to-control-plane/pull/146) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added `--run-release-phase` option to `deploy-image` command to run release script before deploying (same step as in `promote-app-from-upstream` command). [PR 146](https://github.com/shakacode/heroku-to-control-plane/pull/146) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Changed

- Template substitution (used by `apply-template` and `setup-app` commands) now uses double braces (e.g., `APP_ORG` -> `{{APP_ORG}}`). This change is backwards compatible. [PR 146](https://github.com/shakacode/heroku-to-control-plane/pull/146) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Renamed template substitution variable `APP_GVC` to `{{APP_NAME}}` (used by `apply-template` and `setup-app` commands). This change is backwards compatible. [PR 146](https://github.com/shakacode/heroku-to-control-plane/pull/146) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `setup-app` command now automatically binds the app to the secrets policy, as long as both the identity and the policy exist. Added `--skip-secret-access-binding` option to prevent this behavior. [PR 146](https://github.com/shakacode/heroku-to-control-plane/pull/146) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Local API token is now refreshed when it is about to expire. [PR 146](https://github.com/shakacode/heroku-to-control-plane/pull/146) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `apply-template` command now exits with non-zero code if failed to apply any templates. [PR 146](https://github.com/shakacode/heroku-to-control-plane/pull/146) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.3.0] - 2024-03-19

### Fixed

- Fixed issue where cpln profile was not switched back to `default` if an error happened while running `copy-image-from-upstream` command. [PR 135](https://github.com/shakacode/heroku-to-control-plane/pull/135) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed issue that didn't allow using upstream with `match_if_app_name_starts_with` set to `true` in `copy-image-from-upstream` command. [PR 136](https://github.com/shakacode/heroku-to-control-plane/pull/136) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Added

- Added `--no-clean-on-failure` option to `run:detached` command to skip deletion of failed workload run. [PR 133](https://github.com/shakacode/heroku-to-control-plane/pull/133) by [Justin Gordon](https://github.com/justin808) and [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added `--domain` option to `maintenance`, `maintenance:on` and `maintenance:off` commands. [PR 131](https://github.com/shakacode/heroku-to-control-plane/pull/131) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added `default_domain` config to specify domain for `maintenance`, `maintenance:on` and `maintenance:off` commands. [PR 131](https://github.com/shakacode/heroku-to-control-plane/pull/131) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added option to specify upstream for `copy-image-from-upstream` command through `CPLN_UPSTREAM` env var. [PR 138](https://github.com/shakacode/heroku-to-control-plane/pull/138) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Changed

- `build-image` command now accepts extra options and passes them to `docker build`. [PR 126](https://github.com/shakacode/heroku-to-control-plane/pull/126) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `CPLN_ORG_UPSTREAM` env var now takes precedence over config from `controlplane.yml` in `copy-image-from-upstream` command. [PR 137](https://github.com/shakacode/heroku-to-control-plane/pull/137) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `info` command now works properly for apps with `match_if_app_name_starts_with` set to `true`.[PR 139](https://github.com/shakacode/heroku-to-control-plane/pull/139) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- `info` command now lists workloads in the same order as `controlplane.yml`. [PR 139](https://github.com/shakacode/heroku-to-control-plane/pull/139) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Improved domain workload matching for `maintenance`, `maintenance:on` and `maintenance:off` commands (instead of matching only by workload, it now matches by org + app + workload, which is more accurate). [PR 140](https://github.com/shakacode/heroku-to-control-plane/pull/140) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.2.0] - 2024-01-03

### Fixed

- Fixed issue where `info` command does not respect `CPLN_ORG` env var. [PR 88](https://github.com/shakacode/heroku-to-control-plane/pull/88) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed issues with running `cpl --version` and `cpl --help` where no configuration file exists. [PR 100](https://github.com/shakacode/heroku-to-control-plane/pull/100) by [Mostafa Ahangarha](https://github.com/ahangarha).
- Fixed issue where `delete` command fails to delete apps with volumesets. [PR 123](https://github.com/shakacode/heroku-to-control-plane/pull/123) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Added

- Added `--org` option to all commands. [PR 88](https://github.com/shakacode/heroku-to-control-plane/pull/88) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added option to set the app with a `CPLN_APP` env var. [PR 88](https://github.com/shakacode/heroku-to-control-plane/pull/88) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Show `org` and `app` on every command excluding `info`, `version`, `maintenance`, `env`, `ps`, and `latest_image`. [PR 94](https://github.com/shakacode/heroku-to-control-plane/pull/94) by [Mostafa Ahangarha](https://github.com/ahangarha).
- Added option to only use `CPLN_ORG` and `CPLN_APP` env vars if `allow_org_override_by_env` and `allow_app_override_by_env` configs are set to `true` in `controlplane.yml`. [PR 109](https://github.com/shakacode/heroku-to-control-plane/pull/109) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added `CPLN_LOCATION` env variable and `--location` option for `apply-template`, `ps`, `run`, `run:detached`. [PR 105](https://github.com/shakacode/heroku-to-control-plane/pull/105) by [Mostafa Ahangarha](https://github.com/ahangarha).
- Added `generate` command for creating basic Control Plane configuration directory. [PR 116](https://github.com/shakacode/heroku-to-control-plane/pull/116) by [Mostafa Ahangarhga](https://github.com/ahangarha).
- Added `--trace` option to all commands for more detailed logs. [PR 124](https://github.com/shakacode/heroku-to-control-plane/pull/124) by [justin808](https://github.com/justin808)
- Added better error message to check the org name in case of a 403 error. [PR 124](https://github.com/justin808) by [justin808](https://github.com/justin808)

### Changed

- `--org` option now takes precedence over `CPLN_ORG` env var, which takes precedence over `cpln_org` from `controlplane.yml`. [PR 88](https://github.com/shakacode/heroku-to-control-plane/pull/88) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Renamed `setup` config into `setup_app_templates`. [PR 112](https://github.com/shakacode/heroku-to-control-plane/pull/112) by [Mostafa Ahangarha](https://github.com/ahangarha).

## [1.1.2] - 2023-10-17

### Fixed

- Fixed failed build on MacOS by adding platform flag and fixed multiple files in yaml document for template. [PR 81](https://github.com/shakacode/heroku-to-control-plane/pull/81) by [justin808](https://github.com/justin808).

### Added

- Added `open-console` command to open the app console on Control Plane. [PR 83](https://github.com/shakacode/heroku-to-control-plane/pull/83) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added option to set the org with a `CPLN_ORG`/`CPLN_ORG_UPSTREAM` env var. [PR 83](https://github.com/shakacode/heroku-to-control-plane/pull/83) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added `--verbose` option to all commands for more detailed logs. [PR 83](https://github.com/shakacode/heroku-to-control-plane/pull/83) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Changed

- Calling `cpl` with no command now shows the help menu. [PR 83](https://github.com/shakacode/heroku-to-control-plane/pull/83) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.1.1] - 2023-09-23

### Fixed

- Fixed issue where API token is not reset when switching profile. [PR 77](https://github.com/shakacode/heroku-to-control-plane/pull/77) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.1.0] - 2023-09-20

### Fixed

- Fixed issue where `copy-image-from-upstream` command does not copy commit. [PR 70](https://github.com/shakacode/heroku-to-control-plane/pull/70) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed issue where an error is not raised if the app is not defined. [PR 73](https://github.com/shakacode/heroku-to-control-plane/pull/73) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed issue where `CPLN_ENDPOINT` is not used if available. [PR 75](https://github.com/shakacode/heroku-to-control-plane/pull/75) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Added

- Added `image_retention_max_qty` config to clean up images based on max quantity with `cleanup-images` command. [PR 72](https://github.com/shakacode/heroku-to-control-plane/pull/72) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Changed

- Updated docs for `run` commands regarding passing arguments at the end. [PR 71](https://github.com/shakacode/heroku-to-control-plane/pull/71) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Renamed `cleanup-old-images` command to `cleanup-images`. [PR 72](https://github.com/shakacode/heroku-to-control-plane/pull/72) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Renamed `old_image_retention_days` config to `image_retention_days`. [PR 72](https://github.com/shakacode/heroku-to-control-plane/pull/72) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.0.4] - 2023-07-21

### Fixed

- Fixed issue where `run` commands fail when not providing image. [PR 68](https://github.com/shakacode/heroku-to-control-plane/pull/68) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.0.3] - 2023-07-07

### Fixed

- Fixed `run` commands when specifying image. [PR 62](https://github.com/shakacode/heroku-to-control-plane/pull/62) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed `run:cleanup` command for non-interactive workloads. [PR 63](https://github.com/shakacode/heroku-to-control-plane/pull/63) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed `run:cleanup` command for all apps that start with name. [PR 64](https://github.com/shakacode/heroku-to-control-plane/pull/64) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed `cleanup-old-images` command for all apps that start with name. [PR 65](https://github.com/shakacode/heroku-to-control-plane/pull/65) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed `--help` option. [PR 66](https://github.com/shakacode/heroku-to-control-plane/pull/66) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Added

- Added `--use-local-token` option to `run:detached` command. [PR 61](https://github.com/shakacode/heroku-to-control-plane/pull/61) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.0.2] - 2023-07-02

### Added

- Added steps to migrate to docs. [PR 57](https://github.com/shakacode/heroku-to-control-plane/pull/57) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added `ps:wait` command. [PR 58](https://github.com/shakacode/heroku-to-control-plane/pull/58) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.0.1] - 2023-06-28

### Fixed

- Fixed `cleanup-stale-apps` command when app does not have image. [PR 55](https://github.com/shakacode/heroku-to-control-plane/pull/55) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Changed

- Improved docs. [PR 50](https://github.com/shakacode/heroku-to-control-plane/pull/50) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

## [1.0.0] - 2023-05-29

- Initial release

[Unreleased]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.0.4...v1.1.0
[1.0.4]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/shakacode/heroku-to-control-plane/releases/tag/v1.0.0
