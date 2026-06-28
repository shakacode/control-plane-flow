# AGENTS.md

Canonical agent instructions for `cpflow` (Control Plane Flow).

## Agent Workflow Configuration

Portable shared skills (from
[`shakacode/agent-workflows`](https://github.com/shakacode/agent-workflows))
resolve this repo's commands and policy through:

- **Commands** — run `.agents/bin/<name>` (`setup`, `validate`, `test`, `lint`,
  `docs`); see [`.agents/bin/README.md`](.agents/bin/README.md). A missing script
  means that capability is n/a here.
- **Policy / config** — [`.agents/agent-workflow.yml`](.agents/agent-workflow.yml)
  (base branch, changelog, review gate, coordination backend, and other
  non-command keys).

Validate adoption with `agent-workflow-seam-doctor` (add `--shared
<agent-workflows-root>` when checking user-installed shared skills outside the
checkout).
