# frozen_string_literal: true

require "yaml"

module Command
  class UpdateGithubActions < Base
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

      branch = staging_branch || inferred_staging_branch
      GithubActionsGenerator.start([branch].compact)

      Shell.info("")
      Shell.info("Updated cpflow GitHub Actions wrappers for cpflow #{Cpflow::VERSION}.")
      Shell.info("Next: review the diff and run `bin/test-cpflow-github-flow`.")
      Shell.info("If you run cpflow through Bundler, use `bin/test-cpflow-github-flow bundle exec cpflow`.")
    end

    private

    def staging_branch
      branch = config.options[:staging_branch].to_s.strip
      return nil if branch.empty?

      unless valid_staging_branch?(branch)
        Shell.abort(
          "Invalid --staging-branch value: #{branch.inspect}. " \
          "Use a valid git branch name containing only alphanumerics, dots, slashes, underscores, hyphens, and @."
        )
      end

      branch
    end

    def inferred_staging_branch
      branches = existing_staging_branches
      return if branches.empty? || branches == DEFAULT_STAGING_BRANCHES
      return branches.first if branches.length == 1

      Shell.warn(
        "Existing staging workflow has multiple custom push branches: #{branches.join(', ')}. " \
        "Run with --staging-branch BRANCH if only one branch should auto-deploy staging."
      )

      nil
    end

    def existing_staging_branches
      return [] unless STAGING_WORKFLOW_PATH.file?

      workflow = YAML.load_file(STAGING_WORKFLOW_PATH, aliases: true)
      workflow_on = workflow["on"] || workflow[true] || {}
      Array(workflow_on.dig("push", "branches")).map(&:to_s)
    rescue Psych::SyntaxError => e
      Shell.warn(
        "Could not parse #{STAGING_WORKFLOW_PATH}: #{e.message}. " \
        "Run with --staging-branch BRANCH if staging should use a custom branch."
      )
      []
    end

    def valid_staging_branch?(branch)
      return false unless branch.match?(%r{\A[a-zA-Z0-9._/@-]+\z})

      valid_git_branch_shape?(branch) && valid_git_branch_components?(branch)
    end

    def valid_git_branch_shape?(branch)
      return false if branch.start_with?("-", "/", ".")
      return false if branch.end_with?("/", ".")
      return false if branch.include?("@{")

      !branch.include?("..")
    end

    def valid_git_branch_components?(branch)
      branch.split("/").none? do |component|
        component.empty? || component.start_with?(".") || component.end_with?(".lock")
      end
    end
  end
end
