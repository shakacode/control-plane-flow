# Agent Workflow Scripts

Thin, repo-owned command wrappers. Shaka's typed contract uses `setup`,
`validate`, and `test`; the remaining scripts are additional repository helpers.
A script that is **absent** means that capability is n/a here.

| Script | Purpose | This repo runs |
| --- | --- | --- |
| `setup` | Install dependencies | `bundle install` |
| `validate` | Pre-push gate (run before pushing) | ShellCheck, then `bundle exec rake` (rspec + rubocop) |
| `test` | Run tests | `bundle exec rspec` |
| `lint` | Lint / format (pass `-A` to fix) | `bundle exec rubocop` |
| `docs` | Check generated command docs | `bundle exec rake check_command_docs` |
| `build` | Build / type-check | n/a (gem) |

`validate` requires ShellCheck to be installed and available as `shellcheck` on
`PATH`.

`script/check_shell_scripts` checks every Git-tracked `.sh` and `.bash` file,
plus the extensionless shell entrypoints declared in its
`extensionless_shell_files` array. It does not infer script languages from
shebangs. When adding, renaming, or removing an extensionless shell script,
update that array and its inventory regression test; use a `.sh` or `.bash`
suffix for automatic inclusion. Declared paths must remain tracked and readable.
Unlisted extensionless files and non-shell files are outside this check.

Canonical typed Shaka policy lives in
[`../agent-workflow.yml`](../agent-workflow.yml). The GitHub Actions dependency allowlist lives in
[`../trusted-actions.yml`](../trusted-actions.yml). Additional agent-binding repository policy,
including the release-QA runbook reference, lives in [`../../AGENTS.md`](../../AGENTS.md).
