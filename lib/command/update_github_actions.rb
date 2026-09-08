# frozen_string_literal: true

require "yaml"

require_relative "staging_branch_validation"

module Command
  class UpdateGithubActions < Base # rubocop:disable Metrics/ClassLength
    include StagingBranchValidation

    NAME = "update-github-actions"
    OPTIONS = [staging_branch_option, {
      name: :workflows,
      params: {
        type: :array, banner: "FILE...",
        desc: "Explicitly add or replace these generated workflow filenames (default: preserve all workflows)"
      }
    }].freeze
    DESCRIPTION = "Regenerates GitHub Actions files for the installed cpflow version"
    LONG_DESCRIPTION = <<~DESC.freeze
      Refreshes local composite actions and helper files from the installed gem.
      All top-level workflows are preserved by default, including their refs,
      triggers, permissions, and deployment ownership. Use --workflows FILE...
      to explicitly add or replace named generated workflows. Replacement resets
      each selected workflow to its template and matching v#{Cpflow::VERSION} ref;
      review and reapply any downstream customizations in the same PR.

      Selecting cpflow-deploy-staging.yml preserves a single existing push branch
      or the default main/master pair. Missing or ambiguous branches require
      --staging-branch BRANCH. This option requires selecting the staging workflow.

      A differing existing bin/test-cpflow-github-flow blocks all writes. Move
      downstream checks to executable bin/test-cpflow-github-flow-custom and
      remove or rename the old validator before updating. The generated validator
      invokes that extension after its baseline checks; the extension is never
      generated or overwritten. See docs/ci-automation.md for migration guidance.
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Refresh actions/helpers while preserving downstream workflows
      cpflow update-github-actions

      # When running cpflow through Bundler
      bundle exec cpflow update-github-actions

      # Explicitly replace the review-app wrapper
      cpflow update-github-actions --workflows cpflow-deploy-review-app.yml

      # Explicitly add or replace staging deployment from develop
      cpflow update-github-actions --workflows cpflow-deploy-staging.yml --staging-branch develop
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
      workflows = selected_workflows
      branch = selected_staging_branch(workflows)
      abort_if_custom_validator!
      GithubActionsGenerator.new([branch].compact, workflows: workflows).invoke_all

      print_post_update_message
    end

    private

    def selected_workflows
      available = GenerateGithubActions.generated_files.grep(%r{\A\.github/workflows/}).map do |path|
        File.basename(path)
      end
      selected = Array(config.options[:workflows])
      unknown = selected - available
      Shell.abort("Unknown --workflows: #{unknown.join(', ')}. Available: #{available.join(', ')}") if unknown.any?
      selected
    end

    def selected_staging_branch(workflows)
      branch = staging_branch
      return branch || inferred_staging_branch if workflows.include?(STAGING_WORKFLOW_PATH.basename.to_s)

      Shell.abort("--staging-branch requires --workflows cpflow-deploy-staging.yml") if branch
      nil
    end

    def abort_if_custom_validator!
      path = "bin/test-cpflow-github-flow"
      return unless File.exist?(path)
      return if File.binread(path) == File.binread(GenerateGithubActions.source_file(path))

      Shell.abort(<<~MESSAGE)
        #{path} differs from the current generated validator. No files were updated.
        Move downstream checks to executable bin/test-cpflow-github-flow-custom, then remove or rename
        #{path} and retry. See docs/ci-automation.md for the legacy validator migration.
      MESSAGE
    end

    def abort_if_no_generated_files!
      return if GenerateGithubActions.generated_files.any? { |path| File.exist?(path) }

      Shell.abort(<<~MESSAGE)
        No generated cpflow GitHub Actions files found in this repository.
        Run `cpflow generate-github-actions` first to create the wrappers,
        then use `cpflow update-github-actions` after future gem upgrades.
      MESSAGE
    end

    def print_post_update_message
      Shell.info("")
      Shell.info("Updated cpflow GitHub Actions files for cpflow #{Cpflow::VERSION}.")
      Shell.info("Preserved unselected workflows; review their refs and compatibility before committing.")
      Shell.info("Next: review the diff and run `bin/test-cpflow-github-flow`.")
      Shell.info("If you run cpflow through Bundler, use `bin/test-cpflow-github-flow bundle exec cpflow`.")
    end

    def inferred_staging_branch
      branches = existing_staging_branches
      return if branches.sort == DEFAULT_STAGING_BRANCHES.sort
      return branches.first if branches.length == 1 && valid_staging_branch?(branches.first)

      Shell.abort("Cannot infer staging deployment branch. Pass --staging-branch BRANCH to explicitly set it.")
    end

    def existing_staging_branches
      push = parsed_staging_workflow_on["push"]
      branches = push.is_a?(Hash) ? push["branches"] : nil
      branches.is_a?(Array) && branches.all?(String) ? branches : []
    end

    def parsed_staging_workflow_on
      return {} unless STAGING_WORKFLOW_PATH.file?

      workflow = YAML.load_file(STAGING_WORKFLOW_PATH, aliases: true)
      workflow_on = workflow.is_a?(Hash) ? workflow["on"] || workflow[true] : nil
      workflow_on.is_a?(Hash) ? workflow_on : {}
    rescue Psych::SyntaxError => e
      Shell.abort(
        "Could not parse #{STAGING_WORKFLOW_PATH}: #{e.message}. " \
        "Pass --staging-branch BRANCH to explicitly replace its staging deployment branch."
      )
    end
  end
end
