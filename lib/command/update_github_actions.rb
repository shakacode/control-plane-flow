# frozen_string_literal: true

require "yaml"

require_relative "staging_branch_validation"

module Command
  class UpdateGithubActions < Base
    include StagingBranchValidation

    NAME = "update-github-actions"
    OPTIONS = [staging_branch_option].freeze
    DESCRIPTION = "Regenerates generated GitHub Actions wrappers for the installed cpflow version"
    LONG_DESCRIPTION = <<~DESC.freeze
      Regenerates the generated cpflow GitHub Actions wrappers and helper files
      from the currently installed cpflow gem. Use this after updating the
      cpflow gem so checked-in workflow wrappers move to the matching upstream
      release tag, for example `v#{Cpflow::VERSION}`.

      If the existing generated staging workflow uses a custom single staging
      branch, the command preserves it. Pass `--staging-branch BRANCH` to set or
      replace the generated staging branch explicitly.
    DESC
    EXAMPLES = <<~EX
      ```sh
      # After updating the cpflow gem, refresh generated GitHub Actions wrappers
      cpflow update-github-actions

      # When running cpflow through Bundler
      bundle exec cpflow update-github-actions

      # Preserve or set a custom staging branch
      cpflow update-github-actions --staging-branch develop
      ```
    EX
    WITH_INFO_HEADER = false
    VALIDATIONS = [].freeze
    REQUIRES_STARTUP_CHECKS = false

    DEFAULT_STAGING_BRANCHES = %w[main master].freeze
    STAGING_WORKFLOW_PATH = Pathname.new(".github/workflows/cpflow-deploy-staging.yml")

    def call
      GenerateGithubActions.ensure_template_root!
      abort_if_no_generated_files!

      branch = staging_branch || inferred_staging_branch
      GithubActionsGenerator.start([branch].compact)

      print_post_update_message
    end

    private

    def abort_if_no_generated_files!
      return if GenerateGithubActions.generated_files.any? { |path| File.exist?(path) }

      Shell.abort(
        "No generated cpflow GitHub Actions files found in this repository. " \
        "Run `cpflow generate-github-actions` first to create the wrappers, " \
        "then use `cpflow update-github-actions` after future gem upgrades."
      )
    end

    def print_post_update_message
      Shell.info("")
      Shell.info("Updated cpflow GitHub Actions wrappers for cpflow #{Cpflow::VERSION}.")
      Shell.info("Next: review the diff and run `bin/test-cpflow-github-flow`.")
      Shell.info("If you run cpflow through Bundler, use `bin/test-cpflow-github-flow bundle exec cpflow`.")
    end

    def inferred_staging_branch
      branches = existing_staging_branches
      return if branches.empty? || branches.sort == DEFAULT_STAGING_BRANCHES.sort
      return branches.first if branches.length == 1

      Shell.warn(
        "Existing staging workflow has multiple custom push branches: #{branches.join(', ')}. " \
        "Run with --staging-branch BRANCH if only one branch should auto-deploy staging."
      )

      nil
    end

    def existing_staging_branches
      Array(parsed_staging_workflow_on.dig("push", "branches")).map(&:to_s)
    end

    def parsed_staging_workflow_on
      return {} unless STAGING_WORKFLOW_PATH.file?

      workflow = YAML.load_file(STAGING_WORKFLOW_PATH, aliases: true)
      return {} unless workflow.is_a?(Hash)

      workflow_on = workflow["on"] || workflow[true]
      workflow_on.is_a?(Hash) ? workflow_on : {}
    rescue Psych::SyntaxError => e
      warn_unparseable_staging_workflow(e)
      {}
    end

    def warn_unparseable_staging_workflow(error)
      Shell.warn(
        "Could not parse #{STAGING_WORKFLOW_PATH}: #{error.message}. " \
        "Run with --staging-branch BRANCH if staging should use a custom branch."
      )
    end
  end
end
