# AI Rollout Prompt for Control Plane GitHub Flow

Use this file when you want an AI agent to add the reusable `cpflow` review-app,
staging, and production-promotion flow to a repository.

If `cpflow` is already installed in the target repo, you can print the current
copy-paste version of this prompt with:

```sh
cpflow ai-github-flow-prompt
```

That local-only command works even before `cpln` is installed and fills in the
repo-name default app prefix for the current checkout. You can also run
`cpflow github-flow-readiness` first to check the same blocker categories the
prompt tells the agent to stop on.

## Recommended Prompt

```text
Set up Control Plane GitHub Flow for this repo. Start with `cpflow github-flow-readiness` and stop on any reported blockers. The repo must be deployable from a clean clone: published package versions, complete runtime scaffold, and a production Dockerfile that can build the app. If any package version is unpublished, inaccessible from CI, or requires credentials that are not already modeled in the repo or GitHub settings, stop and report the blocker instead of generating workflow files. If the repo is a legacy sample pinned to an obsolete Ruby or Bundler toolchain, if it does not even have a production Dockerfile yet, or if it is a monorepo without an already-decided single app boundary for this flow, stop and report that as a prerequisite instead of forcing the rollout.

If `.controlplane/` is missing, run `cpflow generate`. Treat the generated app names as the repo-name default and rename them only if the project needs a different prefix. Then run `cpflow generate-github-actions`, keep review apps opt-in via `/deploy-review-app`, use `STAGING_APP_BRANCH` or the default branch for staging deploys, and list the GitHub secrets and variables that must be configured.

Keep Node available in the final image if asset compilation or SSR depends on ExecJS, Yarn, `pnpm`, or npm after the main install layer. Make sure the generated Dockerfile uses a Ruby base image compatible with the app's declared Ruby requirement. Preserve repo-defined frontend build hooks: if `config/shakapacker.yml` defines a `precompile_hook`, or React on Rails enables `config.auto_load_bundle = true`, confirm the generated Dockerfile runs that codegen step before `rails assets:precompile`. If `config/database.yml` shows SQLite in production, confirm that the generated scaffold uses persistent `db` and `storage` volumes plus a release script that runs `rails db:prepare`; otherwise keep the default Postgres workload. If the public workload is not named `rails`, set `PRIMARY_WORKLOAD` or adjust the generated workflows. Inspect the Dockerfile and package sources for private GitHub dependencies or `RUN --mount=type=ssh`; if present, wire `DOCKER_BUILD_SSH_KEY`, optionally set `DOCKER_BUILD_SSH_KNOWN_HOSTS` for non-GitHub SSH hosts, and keep `DOCKER_BUILD_EXTRA_ARGS` to newline-delimited single tokens such as `--build-arg=FOO=bar`.

Run the real local validations you can: Docker build if feasible, repo tests or smoke checks, YAML validation, and any CI-equivalent build steps. Push the branch and check the GitHub Actions results. Only stop early for a real external blocker or a product decision that changes scope.
```

## Hard Stop Conditions

Stop and report the blocker instead of generating `cpflow-*` workflow files when:

- the repo is a partial sample or generator snapshot rather than a deployable app
- the app depends on unpublished or inaccessible gem or npm package versions
- the repo is pinned to a legacy Ruby or Bundler toolchain that you cannot validate in the current environment
- there is no production Dockerfile and the app's production build path is still undefined
- the repo is a monorepo or contains multiple deployable apps and the flow target is not already decided
- the local checkout does not match the intended remote repository
- the app needs product decisions about workload shape, secrets, or promotion behavior that are not already implied by the repo

## Definition of Done

The rollout is done when all of the following are true:

- `.controlplane/` exists and matches the actual app shape
- `.github/actions/cpflow-*` and `.github/workflows/cpflow-*` are in place
- review apps are opt-in, staging auto-deploys from one branch, and production promotion is manual
- required GitHub secrets and variables are documented for the repo
- the production image build path is validated for the real app
- repo-specific runtime concerns are handled, such as SQLite volumes, sidekiq workloads, SSR runtime Node access, React on Rails pack generation hooks, or private dependency fetches
- the branch is pushed and the relevant GitHub checks are either green or blocked only by an external system failure

## React on Rails Notes

For React on Rails and React on Rails Pro apps, explicitly verify:

- SSR or renderer workloads do not lose Node or package-manager access in the final image
- sidecar renderers or worker processes bind to `0.0.0.0`, not container-local `localhost`
- writable caches, bundle outputs, or SQLite files live in runtime-writable paths
- old demo repos are treated as legacy exceptions unless they can still build from a clean clone
