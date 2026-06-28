# Agent Workflow Scripts

Standard entry points that portable agent-workflow skills call, so a skill can
run `.agents/bin/<name>` in any repo without knowing this repo's specific
commands. Each script is a thin, repo-owned wrapper. A script that is **absent**
means that capability is n/a here.

| Script | Purpose | This repo runs |
| --- | --- | --- |
| `setup` | Install dependencies | `bundle install` |
| `validate` | Pre-push gate (run before pushing) | `bundle exec rake` (rspec + rubocop) |
| `test` | Run tests | `bundle exec rspec` |
| `lint` | Lint / format (pass `-A` to fix) | `bundle exec rubocop` |
| `docs` | Check generated command docs | `bundle exec rake check_command_docs` |
| `build` | Build / type-check | n/a (gem) |

Non-command policy lives in [`../agent-workflow.yml`](../agent-workflow.yml).
