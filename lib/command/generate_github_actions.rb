# frozen_string_literal: true

require "json"
require "pathname"

require_relative "generator_helpers"
require_relative "staging_branch_validation"

module Command
  class GithubActionsGenerator < Thor::Group
    include Thor::Actions
    include GeneratorHelpers

    argument :staging_branch, type: :string, required: false

    def copy_files
      relative_paths = generated_files
      replacements = template_variables
      copy_generated_files(relative_paths)
      substitute_template_variables(relative_paths, replacements)
      make_shell_scripts_executable(relative_paths)
    end

    def self.source_root
      Cpflow.root_path.join("lib")
    end

    private

    def copy_generated_files(relative_paths)
      relative_paths.each do |relative_path|
        empty_directory(File.dirname(relative_path), verbose: false)
        copy_file(
          GenerateGithubActions.source_file(relative_path),
          relative_path,
          force: true,
          verbose: ENV.fetch("HIDE_COMMAND_OUTPUT", nil) != "true"
        )
      end
    end

    def template_variables
      {
        "__CPFLOW_GITHUB_ACTIONS_REF__" => cpflow_github_actions_ref,
        "__CPFLOW_MINOR_SERIES__" => cpflow_minor_series,
        "__STAGING_BRANCH_FILTER__" => staging_branch_filter,
        "__STAGING_BRANCH_DEFAULT__" => staging_branch_default
      }
    end

    def generated_files
      # Keep file discovery centralized on the command class so existence checks and
      # Thor's template copy list cannot drift.
      GenerateGithubActions.generated_files
    end

    def staging_branch_filter
      branches = staging_branch ? [staging_branch] : %w[main master]
      # JSON string literals are valid YAML flow-sequence scalars, so this keeps
      # the generated branch list readable while still escaping branch names.
      branches.map(&:to_json).join(", ")
    end

    def staging_branch_default
      staging_branch.to_s
    end

    def cpflow_github_actions_ref
      ref = ENV.fetch("CPFLOW_GITHUB_ACTIONS_REF", default_cpflow_github_actions_ref).to_s.strip
      return default_cpflow_github_actions_ref if ref.empty?

      if ref.match?(/[[:space:]]/)
        Shell.abort("Invalid CPFLOW_GITHUB_ACTIONS_REF: #{ref.inspect}. Refs cannot contain whitespace.")
      end

      ref
    end

    def default_cpflow_github_actions_ref
      "v#{::Cpflow::VERSION}"
    end

    # Returns e.g. "5.0.x" for the version-locking placeholder in cpflow-help.md.
    def cpflow_minor_series
      "#{::Cpflow::VERSION.split('.').first(2).join('.')}.x"
    end
  end

  class GenerateGithubActions < Base
    include StagingBranchValidation

    NAME = "generate-github-actions"
    OPTIONS = [staging_branch_option, force_option].freeze
    DESCRIPTION = "Creates GitHub Actions templates for review apps, staging deploys, and production promotion"
    LONG_DESCRIPTION = <<~DESC
      Creates GitHub Actions templates for a Heroku Flow style Control Plane pipeline:
      - on-demand review apps for pull requests
      - automatic staging deploys from your main branch
      - manual promotion from staging to production
      - nightly cleanup and PR help workflows

      It also copies cpflow's composite actions into `.github/actions/cpflow-*`
      so every local `uses:` target is checked in and can be audited directly.

      Pass `--staging-branch BRANCH` when staging should auto-deploy from a branch
      other than `main` or `master`; the generator will bake that branch into the
      GitHub Actions push trigger and use it as the default STAGING_APP_BRANCH.
      Pass `--force` to overwrite existing generated files. Prefer
      `cpflow update-github-actions` after bumping the cpflow gem in a downstream
      repo.
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Creates workflow wrappers, local composite actions, and validation helpers
      cpflow generate-github-actions

      # Creates the flow with staging deploys triggered from develop
      cpflow generate-github-actions --staging-branch develop

      # Overwrites existing generated GitHub Actions files from the installed cpflow gem
      cpflow generate-github-actions --force
      ```
    EX
    WITH_INFO_HEADER = false
    VALIDATIONS = [].freeze
    REQUIRES_STARTUP_CHECKS = false

    # Resolve source roots from __dir__ rather than Cpflow.root_path because this file is
    # loaded before `module Cpflow` finishes defining its class methods.
    REPOSITORY_ROOT = Pathname.new(File.expand_path("../..", __dir__))
    TEMPLATE_ROOT = Pathname.new(File.expand_path("../github_flow_templates", __dir__))
    ACTIONS_ROOT = REPOSITORY_ROOT.join(".github/actions")

    def self.generated_file_sources
      ensure_template_root!

      template_sources = files_beneath(TEMPLATE_ROOT).to_h do |source|
        [source.relative_path_from(TEMPLATE_ROOT).to_s, source]
      end
      action_sources = files_beneath(ACTIONS_ROOT, "cpflow-*/**/*").to_h do |source|
        [source.relative_path_from(REPOSITORY_ROOT).to_s, source]
      end

      template_sources.merge(action_sources).sort.to_h.freeze
    end

    def self.generated_files
      generated_file_sources.keys.freeze
    end

    def self.source_file(relative_path)
      generated_file_sources.fetch(relative_path).to_s
    end

    def self.ensure_template_root!
      raise "cpflow template directory not found: #{TEMPLATE_ROOT}" unless TEMPLATE_ROOT.directory?
      raise "cpflow action directory not found: #{ACTIONS_ROOT}" unless ACTIONS_ROOT.directory?
    end

    def self.files_beneath(root, pattern = "**/*")
      Dir.glob(root.join(pattern).to_s, File::FNM_DOTMATCH)
         .select { |path| File.file?(path) }
         .map { |path| Pathname.new(path) }
         .sort
    end

    def call
      self.class.ensure_template_root!
      branch = staging_branch

      if (existing = existing_files).any? && !force?
        files = existing.map { |path| "- #{path}" }.join("\n")
        Shell.warn("The following files already exist:\n#{files}\n\n" \
                   "Remove or rename them before running `cpflow #{NAME}` again, " \
                   "or run `cpflow update-github-actions` after updating the cpflow gem.")
        return
      end

      GithubActionsGenerator.start([branch].compact)
    end

    private

    def existing_files
      @existing_files ||= self.class.generated_files.select { |path| File.exist?(path) }
    end

    def force?
      config.options[:force]
    end
  end
end
