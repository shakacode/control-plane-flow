# frozen_string_literal: true

require "json"
require "pathname"

require_relative "generator_helpers"

module Command
  class GithubActionsGenerator < Thor::Group
    include Thor::Actions
    include GeneratorHelpers

    argument :staging_branch, type: :string, required: false

    def copy_files
      copy_template_files(generated_files)
      substitute_template_variables(generated_files)
      make_shell_scripts_executable(generated_files)
    end

    def self.source_root
      Cpflow.root_path.join("lib")
    end

    private

    def copy_template_files(relative_paths)
      relative_paths.each do |relative_path|
        empty_directory(File.dirname(relative_path), verbose: false)
        copy_file(
          File.join("github_flow_templates", relative_path),
          relative_path,
          force: true,
          verbose: ENV.fetch("HIDE_COMMAND_OUTPUT", nil) != "true"
        )
      end
    end

    def template_variables
      {
        "__CPFLOW_VERSION__" => ::Cpflow::VERSION,
        "__STAGING_BRANCH_FILTER__" => staging_branch_filter,
        "__STAGING_APP_BRANCH_EXPRESSION__" => staging_app_branch_expression
      }
    end

    def generated_files
      GenerateGithubActions.generated_files
    end

    def staging_branch_filter
      branches = staging_branch ? [staging_branch] : %w[main master]
      # JSON string literals are valid YAML flow-sequence scalars, so this keeps
      # the generated branch list readable while still escaping branch names.
      branches.map(&:to_json).join(", ")
    end

    def staging_app_branch_expression
      return "${{ vars.STAGING_APP_BRANCH }}" unless staging_branch

      "${{ vars.STAGING_APP_BRANCH || '#{staging_branch}' }}"
    end
  end

  class GenerateGithubActions < Base
    NAME = "generate-github-actions"
    OPTIONS = [staging_branch_option].freeze
    DESCRIPTION = "Creates GitHub Actions templates for review apps, staging deploys, and production promotion"
    LONG_DESCRIPTION = <<~DESC
      Creates GitHub Actions templates for a Heroku Flow style Control Plane pipeline:
      - on-demand review apps for pull requests
      - automatic staging deploys from your main branch
      - manual promotion from staging to production
      - nightly cleanup and PR help workflows

      Pass `--staging-branch BRANCH` when staging should auto-deploy from a branch
      other than `main` or `master`; the generator will bake that branch into the
      GitHub Actions push trigger and use it as the default STAGING_APP_BRANCH.
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Creates .github/actions and .github/workflows files for the Control Plane flow
      cpflow generate-github-actions

      # Creates the flow with staging deploys triggered from develop
      cpflow generate-github-actions --staging-branch develop
      ```
    EX
    WITH_INFO_HEADER = false
    VALIDATIONS = [].freeze
    REQUIRES_STARTUP_CHECKS = false

    # Resolve template root from __dir__ rather than Cpflow.root_path because this file is
    # loaded before `module Cpflow` finishes defining its class methods.
    TEMPLATE_ROOT = Pathname.new(File.expand_path("../github_flow_templates", __dir__))

    def self.generated_files
      ensure_template_root!

      Dir.glob(TEMPLATE_ROOT.join("**", "*").to_s, File::FNM_DOTMATCH)
         .select { |path| File.file?(path) }
         .map { |path| Pathname.new(path).relative_path_from(TEMPLATE_ROOT).to_s }
         .sort
         .freeze
    end

    def self.ensure_template_root!
      raise "cpflow template directory not found: #{TEMPLATE_ROOT}" unless TEMPLATE_ROOT.directory?
    end

    def call
      self.class.ensure_template_root!
      branch = staging_branch

      if existing_files.any?
        files = existing_files.map { |path| "- #{path}" }.join("\n")
        Shell.warn("The following files already exist:\n#{files}\n\n" \
                   "Remove or rename them before running `cpflow #{NAME}` again.")
        return
      end

      GithubActionsGenerator.start([branch].compact)
    end

    private

    def existing_files
      @existing_files ||= self.class.generated_files.select { |path| File.exist?(path) }
    end

    def staging_branch
      branch = config.options[:staging_branch].to_s.strip
      return nil if branch.empty?

      unless valid_staging_branch?(branch)
        Shell.abort(
          "Invalid --staging-branch value: #{branch.inspect}. " \
          "Use a valid git branch name containing only alphanumerics, dots, slashes, underscores, and hyphens."
        )
      end

      branch
    end

    def valid_staging_branch?(branch)
      return false unless branch.match?(%r{\A[a-zA-Z0-9._/-]+\z})

      valid_git_branch_shape?(branch) && valid_git_branch_components?(branch)
    end

    def valid_git_branch_shape?(branch)
      return false if branch.start_with?("-", "/", ".")
      return false if branch.end_with?("/", ".")

      !branch.include?("..")
    end

    def valid_git_branch_components?(branch)
      branch.split("/").none? do |component|
        component.empty? || component.start_with?(".") || component.end_with?(".lock")
      end
    end
  end
end
