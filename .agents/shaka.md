# Shaka configuration

| Identifier | Value |
| --- | --- |
| Package / skill SemVer | `0.1.0.pre.1` |
| Seam contract | `version: 1` |

The package SemVer and contract version are separate identifiers. This file records
the adopted package / skill SemVer; update it when that version changes. The typed
contract is in `agent-workflow.yml`, and `../AGENTS.md` owns repository identity,
trust bootstrap, and human-only delivery and release rules.

## Check configuration edits

Run from the repository root:

`shaka seam check --root . --local`

Checks the current checkout's YAML and fixed-script paths and executable bits. It
does not execute the wrappers and grants no trusted policy authority.

- [Configuration reference](https://github.com/shakacode/shaka/blob/main/docs/settings.md) — every key, its type, and what it controls.
- [Repository setup](https://github.com/shakacode/shaka/blob/main/docs/configure-repository.md) — how this directory was created.
