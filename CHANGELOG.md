# Changelog

All notable changes to this project's source code will be documented in this file. Items under `Unreleased` are upcoming features that will be out in the next version.

## Contributors

Please follow the recommendations outlined at [keepachangelog.com](https://keepachangelog.com). Please use the existing headings and styling as a guide, and add a link for the version diff at the bottom of the file. Also, please update the `Unreleased` link to compare it to the latest release version.

## Versions

## [Unreleased]

Changes since the last non-beta release.

_Please add entries here for your pull requests that are not yet released._

### Fixed

- Fixed issue where an error is not raised if the app is not defined. [PR 73](https://github.com/shakacode/heroku-to-control-plane/pull/73) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

### Changed

- Updated docs for `run` commands regarding passing arguments at the end. [PR 71](https://github.com/shakacode/heroku-to-control-plane/pull/71) by [Rafael Gomes](https://github.com/rafaelgomesxyz).

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

[Unreleased]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.0.4...HEAD
[1.0.4]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/shakacode/heroku-to-control-plane/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/shakacode/heroku-to-control-plane/releases/tag/v1.0.0
