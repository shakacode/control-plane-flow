# Changelog

All notable changes to this project's source code will be documented in this file. Items under `Unreleased` are upcoming features that will be out in the next version.

## Contributors

Please follow the recommendations outlined at [keepachangelog.com](https://keepachangelog.com). Please use the existing headings and styling as a guide, and add a link for the version diff at the bottom of the file. Also, please update the `Unreleased` link to compare it to the latest release version.

## Versions

## [Unreleased]

Changes since the last non-beta release.

_Please add entries here for your pull requests that are not yet released._

### Fixed

- Fixed issue where `info` command does not respect `CPLN_ORG` env var. [PR 88](https://github.com/shakacode/heroku-to-control-plane/pull/88) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Fixed issues with running `cpl --version` and `cpl --help` where no configuration file exists. [PR 100](https://github.com/shakacode/heroku-to-control-plane/pull/100) by [Mostafa Ahangarhga](https://github.com/ahangarha).

### Added

- Added `--org` option to all commands. [PR 88](https://github.com/shakacode/heroku-to-control-plane/pull/88) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Added option to set the app with a `CPLN_APP` env var. [PR 88](https://github.com/shakacode/heroku-to-control-plane/pull/88) by [Rafael Gomes](https://github.com/rafaelgomesxyz).
- Show `org` and `app` on every command excluding `info`, `version`, `maintenance`, `env`, `ps`, and `latest_image`. [PR 94](https://github.com/shakacode/heroku-to-control-plane/pull/94) by [Mostafa Ahangarhga](https://github.com/ahangarha).

### Changed

- `--org` option now takes precedence over `CPLN_ORG` env var, which takes precedence over `cpln_org` from `controlplane.yml`. [PR 88](https://github.com/shakacode/heroku-to-control-plane/pull/88) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

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

[Unreleased]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.1.2...HEAD
[1.1.2]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.0.4...v1.1.0
[1.0.4]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/shakacode/heroku-to-control-plane/releases/tag/v1.0.0
