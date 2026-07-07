# AI Rollout End-to-End Prompt Runbook

Use this internal runbook after publishing a `cpflow` gem when the release
changes the GitHub Actions flow, the AI rollout prompt, readiness checks,
generator output, or React on Rails deployment behavior.

This is not public setup documentation. It is release QA for the maintainer and
agents. The goal is to test whether the published gem plus the recommended
prompt can guide a capable agent through a real React on Rails rollout without
private maintainer context.

## Mindset

Treat the prompt as part of the product. The test is not just "do generated files
exist?" It is "does the prompt cause an agent to make the right install,
readiness, generation, validation, and feedback decisions?"

Use a real downstream React on Rails app. Do not test from the
`control-plane-flow` checkout, and do not let the agent use unpublished local
code unless the explicit goal is prerelease testing.

## Prompt 1: Start the Install and Rollout Test

Use this as the opening prompt in a fresh agent session inside the target React
on Rails app repository:

```text
You are testing published Control Plane Flow version X.Y.Z on this React on Rails app.

Do not use a local `control-plane-flow` checkout or unpublished gem code. Install or invoke the published gem only. Prefer `gem install cpflow -v X.Y.Z`; if the target repo already has a Bundler-managed `cpflow`, use `bundle exec cpflow` only after confirming it resolves to version X.Y.Z. Report a blocker if you cannot install or invoke that published version.
After you verify the correct invocation, use that same invocation for every later `cpflow` command. For example, use `bundle exec cpflow github-flow-readiness` if Bundler was the verified path.

Once `cpflow` is available, run the verified invocation with `ai-github-flow-prompt` and follow the printed recommended prompt exactly. Use that prompt to run readiness, generate or update `.controlplane/`, generate GitHub Actions, preserve React on Rails build behavior, document required GitHub settings, validate locally, push a branch, and open a PR.

Important constraints:
- Start with `cpflow github-flow-readiness` and stop on any real blocker.
- Do not force generated files into an app that is not deployable from a clean clone.
- Do not use production credentials for review-app validation.
- Keep review apps limited to trusted branches in the base repository.
- Preserve React on Rails SSR, pack generation, Node/package-manager access, sidecars, and writable runtime paths.
- Record every place where the prompt or command output was confusing, incomplete, or caused you to guess.
```

This internal test prompt intentionally prefers `gem install cpflow -v X.Y.Z`
because it verifies the published gem. The public rollout prompt may prefer an
app's existing `bundle exec cpflow` path first when the app already manages
`cpflow` through Bundler.

## Prompt 2: Validate the Generated Flow

Use this after the agent opens or prepares the target-app PR:

```text
Now validate the generated Control Plane GitHub Flow in the target app.

Run the strongest local checks available, including `cpflow github-flow-readiness`, `bin/test-cpflow-github-flow`, a Docker build if feasible, and the app's native smoke checks. Then push the branch and inspect the hosted GitHub Actions results.

If credentials are available for a disposable staging/review Control Plane org, validate one trusted-branch review app:
1. confirm the help workflow exposes the expected review-app commands
2. comment `+review-app-deploy` on the target-app PR from an `OWNER`, `MEMBER`, or `COLLABORATOR` account
3. wait for the review-app workflow
4. visit the reported app URL
5. verify the Rails page and React entry point
6. confirm logs are accessible
7. delete the review app and confirm cleanup

Do not test production promotion unless this is an explicit release rehearsal with a disposable production org. Report skipped validations with the exact reason.
```

## Prompt 3: Turn the Results into Product Feedback

Use this after the rollout attempt finishes:

```text
Analyze this AI rollout test as product feedback for Control Plane Flow.

Classify every finding into exactly one bucket:
- Prompt gap: better prompt wording would have prevented the confusion or wrong choice.
- Command gap: `cpflow` should detect, generate, or report something better.
- Generator gap: generated files need a code change or regression spec.
- Docs gap: humans need clearer setup or release guidance.
- Target-app gap: the app is missing a real deploy prerequisite.
- External blocker: credentials, Control Plane availability, GitHub Actions, or registry access blocked the run.

Prefer command or generator fixes over prompt wording when the issue is deterministic. Only suggest prompt changes for repeatable agent-decision failures. Produce a concise follow-up plan with release-blocking items first.
```

## Target App Criteria

Use a real, non-production React on Rails app with:

- a complete Rails runtime scaffold
- a production Dockerfile or a clearly intended generated Dockerfile path
- React on Rails SSR or pack generation behavior worth validating
- a GitHub repository where the agent can push a test branch and open a PR
- disposable Control Plane staging/review credentials

Stop early if the app is already known to be undeployable from a clean clone.
That is target-app feedback unless the prompt failed to identify the blocker.

## React on Rails Observations to Capture

The transcript should show whether the agent handled these without extra
maintainer hints:

- SSR or renderer workloads keep Node and package-manager access where needed.
- React on Rails auto bundle generation or Shakapacker `precompile_hook` behavior
  is preserved before `rails assets:precompile`.
- Sidekiq, renderer, or other process workloads are modeled when needed.
- Exposed sidecar processes bind to `0.0.0.0`, not only `localhost`.
- Runtime-writable paths are used for caches, bundles, SQLite files, and temp
  data.
- The generated Dockerfile uses a Ruby base image compatible with the app.
- Private GitHub dependencies or SSH build mounts are reflected in documented
  GitHub secrets and Docker build settings.

## Result Template

Record the run with this shape:

```markdown
## AI Rollout E2E Result

- cpflow version:
- target app repo:
- target branch/PR:
- agent used:
- prompt source:
- Control Plane org scope:

### Outcome

- published gem install:
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

### Product Feedback

- prompt gaps:
- command/generator gaps:
- docs gaps:
- target-app gaps:
- external blockers:

### Follow-up

- release-blocking:
- should fix soon:
- optional:
```

Keep the transcript or evidence log until all prompt, command, generator, and
docs follow-ups are either resolved or explicitly deferred.
