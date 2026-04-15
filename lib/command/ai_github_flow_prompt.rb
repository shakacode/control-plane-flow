# frozen_string_literal: true

module Command
  class AiGithubFlowPrompt < Base
    NAME = "ai-github-flow-prompt"
    DESCRIPTION = "Prints the recommended AI prompt for adding the Control Plane GitHub Flow to a repo"
    LONG_DESCRIPTION = <<~DESC
      Prints a copy-paste prompt for an AI agent to roll out the reusable Control Plane GitHub Flow:
      - verifies the repo is deployable from a clean clone before generating files
      - scaffolds `.controlplane/` and `cpflow-*` GitHub Actions files when the repo qualifies
      - stops on external blockers or product decisions instead of forcing a broken rollout
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Prints the recommended AI rollout prompt for the current repo
      cpflow ai-github-flow-prompt
      ```
    EX
    WITH_INFO_HEADER = false
    VALIDATIONS = [].freeze
    REQUIRES_STARTUP_CHECKS = false

    def call
      puts prompt
    end

    private

    def prompt
      <<~PROMPT
        Set up Control Plane GitHub Flow for this repo. First verify that the repo is actually deployable from a clean clone: published package versions, complete runtime scaffold, and a production Dockerfile that can build the app. If any package version is unpublished, inaccessible from CI, or requires credentials that are not already modeled in the repo or GitHub settings, stop and report the blocker instead of generating workflow files. If the repo is a legacy sample pinned to an obsolete Ruby or Bundler toolchain, or it does not even have a production Dockerfile yet, stop and report that as a prerequisite instead of forcing the rollout.

        If `.controlplane/` is missing, run `cpflow generate`. Treat the generated app names as the repo-name default (`#{inferred_app_prefix}`) and rename them only if the project needs a different prefix. Then run `cpflow generate-github-actions`, keep review apps opt-in via `/deploy-review-app`, use `STAGING_APP_BRANCH` or the default branch for staging deploys, and list the GitHub secrets and variables that must be configured.

        Keep Node available in the final image if asset compilation or SSR depends on ExecJS, Yarn, `pnpm`, or npm after the main install layer. Make sure the generated Dockerfile uses a Ruby base image compatible with the app's declared Ruby requirement. If `config/database.yml` shows SQLite in production, confirm that the generated scaffold uses persistent `db` and `storage` volumes plus a release script that runs `rails db:prepare`; otherwise keep the default Postgres workload. If the public workload is not named `rails`, set `PRIMARY_WORKLOAD` or adjust the generated workflows. Inspect the Dockerfile and package sources for private GitHub dependencies or `RUN --mount=type=ssh`; if present, wire `DOCKER_BUILD_SSH_KEY` and any needed `DOCKER_BUILD_EXTRA_ARGS`.

        Run the real local validations you can: Docker build if feasible, repo tests or smoke checks, YAML validation, and any CI-equivalent build steps. Push the branch and check the GitHub Actions results. Only stop early for a real external blocker or a product decision that changes scope.
      PROMPT
    end

    def inferred_app_prefix
      sanitized_dirname = File.basename(Dir.pwd)
                              .downcase
                              .gsub(/[^a-z0-9]+/, "-")
                              .gsub(/\A-+|-+\z/, "")

      sanitized_dirname.empty? ? "my-app" : sanitized_dirname
    end
  end
end
