# Contributing

## Installation

Rather than installing `cpflow` as a Ruby gem, install this repo locally and alias the `cpflow` command globally for easier
access, e.g.:

```sh
git clone https://github.com/shakacode/control-plane-flow

# Create an alias in some local shell startup script, e.g., `.profile`, `.bashrc`, etc.
alias cpflow="~/projects/control-plane-flow/bin/cpflow"
```

## Linting

Before committing or pushing code, be sure to:

- Run `bundle exec rake update_command_docs` to sync any doc changes made in the source code to the docs
- Run `bundle exec rubocop -a` to fix any linting errors

You can also install [overcommit](https://github.com/sds/overcommit) and let it automatically check for you:

```sh
gem install overcommit

overcommit --install
```

## Docs Site Dispatch

The `trigger-docs-site.yml` workflow notifies `shakacode/controlplaneflow-com` when docs-related files change on `main`.
It requires these repository secrets:

- `DOCS_DISPATCH_APP_ID`: the GitHub App ID used to create the dispatch token
- `DOCS_DISPATCH_APP_KEY`: the GitHub App private key PEM for that app

GitHub's REST docs for the repository dispatch endpoint list **Contents: Write** as the required repository permission for
GitHub App installation tokens. This is separate from **Actions: Write**, which is used by other workflow APIs. Install
the app on `shakacode/controlplaneflow-com` with **Contents: Write**. If the dispatch succeeds but the docs site does not
rebuild, check the target repo's workflow runs for the matching `docs-updated` event.

Manual runs should be started from `main`; non-main manual dispatches are skipped before token generation or docs-site
notification. The GitHub Actions run can therefore finish without dispatching anything when a non-main ref is selected.
The workflow deduplicates runs by workflow and ref with `cancel-in-progress: true`, so consecutive `main` runs can
supersede one another; that is expected because the newest docs state wins.

If the job fails and the summary shows `Dispatch outcome: skipped`, the dispatch step did not run because an earlier step
failed. Check the `Generate GitHub App token` step first, including the App ID, private key secret, installation, and target
repository permissions.

If a manual dispatch is canceled and no later successful `main` run replaces it, re-trigger the manual run from `main`. If
the run is canceled while the dispatch step is already executing, the target repo may already have received the event; check
the target repo workflow runs before re-triggering. Duplicate dispatches are harmless, but they can rebuild the docs site
twice.

## Testing

See [the spec README](./spec/README.md) for credential-free local examples and the distinction between offline and Control Plane-backed specs.

Specs that use real apps need full access to a Control Plane org. Set it as the `CPLN_ORG` environment variable when running the full suite (or in the `.env` file):

```sh
CPLN_ORG=your-org-for-tests bundle exec rspec
```

Alternatively, you might have a `.envrc` file with:

```sh
export CPLN_ORG=shakacode-heroku-to-control-plane-ci
export RSPEC_RETRY_RETRY_COUNT=1
```

Tests are separated between fast and slow. Slow tests can take a long time and usually involve building / deploying images and waiting for workloads to be ready / not ready, so they should only be run once in a while.

If you add a slow test, tag it with `slow`. Tests without a `slow` tag are considered fast by default.

To run fast tests:

```sh
CPLN_ORG=your-org-for-tests bundle exec rspec --tag ~slow
```

To run slow tests:

```sh
CPLN_ORG=your-org-for-tests bundle exec rspec --tag slow
```

## Debugging

1. Use the `--verbose` option to see more detailed logs.
2. Use the `--trace` option to see full logging of HTTP requests. Warning, this will display keys to your logs or console.
1. Add a breakpoint (`debugger`) to any line of code you want to debug.
2. Modify the `lib/command/test.rb` file to trigger the code you want to test. To simulate a command, you can use
   `run_cpflow_command` (e.g., `run_cpflow_command("deploy-image", "-a", "my-app-name")` would be the same as running
   `cpflow deploy-image -a my-app-name`).
3. Run the `test` command in your test app with a `.controlplane` directory.

```sh
cpflow test
```

## Developing the GitHub flow generator

`cpflow generate-github-actions` copies templates from `lib/github_flow_templates/` into a target repo's `.github/` directory. To work on this feature:

- **Edit the templates in place.** The generator does no string-mangling beyond a small set of substitutions handled in `lib/command/generate_github_actions.rb`; what you put in `lib/github_flow_templates/.github/` is (almost) exactly what ships into a generated repo. Make changes there, not in a generated copy.
- **Surface area to keep consistent.** A change to a PR command (e.g. `+review-app-deploy`) usually touches three places: the trigger workflow (`lib/github_flow_templates/.github/workflows/cpflow-deploy-review-app.yml`), the PR-open quick reference (`cpflow-review-app-help.yml`), and the long-form help (`lib/github_flow_templates/.github/cpflow-help.md`). The AI flow prompt (`lib/command/ai_github_flow_prompt.rb`) also names commands and should be kept in sync.
- **Run the generator spec on every change:**

  ```sh
  bundle exec rspec spec/command/generate_github_actions_spec.rb
  ```

  It generates the templates into a tmp playground and asserts on their contents — most regressions in the templates will fail there.
- **Lint the templates.** Generated workflows are checked with `actionlint` in CI. Install it locally and run `actionlint lib/github_flow_templates/.github/workflows/*.yml` to catch issues before pushing.
- **Test PR-branch workflow edits in a real repo.** Comment-triggered runs (`+review-app-deploy`, `+review-app-delete`, `+review-app-help`) execute the workflow code from the repository's default branch, so they will not exercise your PR-branch changes. Generate the workflows into a downstream test repo, push to a feature branch, then dispatch each affected workflow with `gh`:

  ```sh
  gh workflow run cpflow-deploy-review-app.yml --ref <your-pr-branch> -f pr_number=<pr-number>
  gh workflow run cpflow-delete-review-app.yml --ref <your-pr-branch> -f pr_number=<pr-number>
  gh workflow run cpflow-help-command.yml      --ref <your-pr-branch> -f pr_number=<pr-number>
  ```

## Releasing

See [Releasing the Gem](./docs/releasing.md) for the changelog-first Ruby gem release process. In short: run
`/update-changelog release`, merge the generated changelog PR, then run `bundle exec rake release`. This project
releases only the `cpflow` RubyGem; there is no npm publishing step.
