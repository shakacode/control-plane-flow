# Agent Workflow Scripts

Standard entry points that portable agent-workflow skills call, so a skill can
run `.agents/bin/<name>` in any repo without knowing this repo's specific
commands. Each script is a thin, repo-owned wrapper. A script that is **absent**
means that capability is n/a here.

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

Canonical non-command policy, including the release-QA runbook reference, lives
in [`../agent-workflow.yml`](../agent-workflow.yml). [`../../AGENTS.md`](../../AGENTS.md)
is the thin discovery pointer for portable shared skills and does not duplicate
or override that policy.
