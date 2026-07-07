# AI Rollout End-to-End Test

Run this after publishing a new `cpflow` gem when the release changes the
GitHub Actions flow, the AI rollout prompt, readiness checks, generator output,
or React on Rails deployment behavior.

The mindset is product validation, not only file validation. Treat the AI prompt
as part of the product surface: a capable agent should be able to start from the
recommended prompt, use the published gem, make sensible decisions for a real
React on Rails app, and report blockers without needing private context from the
maintainer.

## Goal

Prove the published `cpflow` gem and the recommended AI rollout prompt can drive
a real React on Rails app through the Control Plane GitHub Flow setup:

1. The agent uses the published `cpflow` gem, not a local checkout.
2. The agent starts from the recommended AI rollout prompt.
3. The target app is a real React on Rails app with a production build path.
4. The generated `.controlplane/` and `.github/workflows/cpflow-*` files match
   the app shape.
5. Local validation, hosted GitHub Actions, and at least one review-app deploy
   are checked.
6. Any confusion, wrong assumptions, or missing safeguards feed back into prompt,
   docs, command, or generator improvements.

## Test Target

Use a real, non-production React on Rails app. Prefer an app that has:

- a complete Rails runtime scaffold
- a production Dockerfile or a clearly intended generated Dockerfile path
- React on Rails SSR or pack generation behavior worth validating
- a GitHub repository where you can push a test branch and open a PR
- disposable Control Plane staging/review credentials

Do not use the `control-plane-flow` checkout as the target app. This test is
meant to validate downstream use from a separate app repository.

## Preflight

Confirm the release is truly published and reachable from a clean downstream
environment:

```sh
gem list -r -a cpflow
gem install cpflow -v X.Y.Z
cpflow version
```

In the target React on Rails app:

1. Start from a clean branch based on the app's current default branch.
2. Make sure the test branch does not already contain local `cpflow` changes.
3. Confirm the repo can run its normal install and smoke checks.
4. Confirm you have disposable GitHub repository secrets and variables for the
   staging/review Control Plane org.
5. Confirm no production Control Plane token is required for the review-app part
   of the test.

If the target app is already known to be undeployable from a clean clone, stop.
That is target-app feedback, not AI prompt feedback, unless the prompt failed to
identify the blocker clearly.

## Agent Run

Start a fresh AI-agent session in the target app repository. Give it only:

1. the target repo and branch
2. the published `cpflow` version to use
3. the recommended prompt from [AI Rollout Prompt for Control Plane GitHub Flow](./ai-github-flow-prompt.md)

Do not add extra implementation hints unless the agent reaches a real blocker.
The point is to learn whether the prompt carries enough context on its own.

The agent should:

1. install or invoke the published `cpflow` gem
2. run `cpflow github-flow-readiness`
3. stop on readiness blockers instead of forcing generated files
4. run `cpflow generate` when `.controlplane/` is missing
5. run `cpflow generate-github-actions`
6. adapt generated config only where the React on Rails app requires it
7. preserve React on Rails pack generation, SSR, and Node/package-manager needs
8. document required GitHub secrets and variables
9. validate the real build path
10. push a branch and open a PR in the target app

## React on Rails Checks

Inspect whether the agent handled the React on Rails specifics without being
prompted manually:

- SSR or renderer workloads keep Node and package-manager access where needed.
- React on Rails auto bundle generation or Shakapacker `precompile_hook` behavior
  is preserved before `rails assets:precompile`.
- Sidekiq, renderer, or other process workloads are modeled when the app needs
  them.
- Any process exposed to sibling workloads binds to `0.0.0.0`, not only
  `localhost`.
- Runtime-writable paths are used for caches, bundles, SQLite files, and
  temporary data.
- The generated Dockerfile uses a Ruby base image compatible with the app.
- Private GitHub dependencies or SSH build mounts are reflected in the documented
  GitHub secrets and Docker build settings.

## Validation

Run the strongest checks that are feasible in the target app:

```sh
cpflow github-flow-readiness
bin/test-cpflow-github-flow
docker build .
```

Also run the app's native smoke checks, for example:

```sh
bundle exec rails zeitwerk:check
bundle exec rails assets:precompile
bundle exec rspec
```

The exact native commands depend on the target app. Record skipped commands and
why they were skipped.

After pushing the target-app PR:

1. Verify GitHub Actions run on the generated `cpflow-*` workflows.
2. Confirm the help workflow comments with the expected review-app commands.
3. Comment `+review-app-deploy` on the PR from a trusted branch in the base repo.
4. Confirm the review-app workflow builds, deploys, and reports the app URL.
5. Visit the review app and verify the main Rails page and React entry point.
6. Confirm logs are available with `cpflow logs` or the equivalent workflow output.
7. Delete the review app and confirm cleanup completes.

If staging credentials are available and safe to use, also validate one staging
deploy from the configured staging branch. Production promotion should remain a
dry inspection unless this is an explicit release rehearsal with a disposable
production org.

## Pass Criteria

The test passes when:

- the agent needed no maintainer-only context to understand the recommended path
- the published gem installed and supplied the expected prompt/readiness/generator
  behavior
- readiness failures, if any, were accurate and actionable
- generated files matched the target app shape
- React on Rails production-build concerns were preserved
- local validation and hosted checks either passed or exposed a specific external
  blocker
- one review app was deployed, manually inspected, and cleaned up
- every prompt, docs, command, or generator improvement discovered during the run
  has a follow-up issue or PR

## Feedback Classification

Classify each finding before changing the prompt:

- **Prompt gap:** The agent made a wrong or confused choice that better prompt
  wording could prevent.
- **Command gap:** `cpflow` should have detected, generated, or reported
  something better.
- **Generator gap:** generated files need a code change or regression spec.
- **Docs gap:** humans need clearer setup or release guidance.
- **Target-app gap:** the app is missing a real deploy prerequisite; do not hide
  this by weakening the prompt.
- **External blocker:** credentials, Control Plane availability, GitHub Actions,
  or registry access blocked the run.

Only update the AI prompt for repeatable agent-decision failures. If a command
can detect the issue deterministically, prefer improving the command and then
mentioning the command behavior in the prompt.

## Result Template

Record the run in the release notes, PR, or issue using this shape:

```markdown
## AI Rollout E2E Result

- cpflow version:
- target app repo:
- target branch/PR:
- agent used:
- prompt source:
- Control Plane org scope:

### Outcome

- readiness:
- generation:
- local validation:
- hosted checks:
- review app deploy:
- review app cleanup:
- staging deploy, if tested:

### React on Rails Findings

- SSR/Node/package manager:
- asset precompile/codegen hooks:
- extra workloads:
- writable paths:
- private dependencies:

### Feedback

- prompt gaps:
- command/generator gaps:
- docs gaps:
- target-app gaps:
- external blockers:

### Follow-up

- merged fixes:
- open issues/PRs:
- release-blocking remaining work:
```

Keep the transcript or a concise evidence log until all prompt and command
follow-ups are resolved.
