# frozen_string_literal: true

require_relative "generator_helpers"

module Command
  class GithubActionsGenerator < Thor::Group
    include Thor::Actions
    include GeneratorHelpers

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

        relative_path
      end
    end

    def template_variables
      {
        "__CPFLOW_VERSION__" => ::Cpflow::VERSION
      }
    end

    def generated_files
      GenerateGithubActions::GENERATED_FILES
    end
  end

  class GenerateGithubActions < Base
    NAME = "generate-github-actions"
    DESCRIPTION = "Creates GitHub Actions templates for review apps, staging deploys, and production promotion"
    LONG_DESCRIPTION = <<~DESC
      Creates GitHub Actions templates for a Heroku Flow style Control Plane pipeline:
      - on-demand review apps for pull requests
      - automatic staging deploys from your main branch
      - manual promotion from staging to production
      - nightly cleanup and PR help workflows
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Creates .github/actions and .github/workflows files for the Control Plane flow
      cpflow generate-github-actions
      ```
    EX
    WITH_INFO_HEADER = false
    VALIDATIONS = [].freeze
    REQUIRES_STARTUP_CHECKS = false

    GENERATED_FILES = [
      ".github/actions/cpflow-build-docker-image/action.yml",
      ".github/actions/cpflow-delete-control-plane-app/action.yml",
      ".github/actions/cpflow-delete-control-plane-app/delete-app.sh",
      ".github/actions/cpflow-setup-environment/action.yml",
      ".github/workflows/cpflow-cleanup-stale-review-apps.yml",
      ".github/workflows/cpflow-delete-review-app.yml",
      ".github/workflows/cpflow-deploy-review-app.yml",
      ".github/workflows/cpflow-deploy-staging.yml",
      ".github/workflows/cpflow-help-command.yml",
      ".github/workflows/cpflow-promote-staging-to-production.yml",
      ".github/workflows/cpflow-review-app-help.yml"
    ].freeze

    def call
      if existing_files.any?
        files = existing_files.map { |path| "- #{path}" }.join("\n")
        Shell.warn("The following files already exist:\n#{files}\n\n" \
                   "Remove or rename them before running `cpflow #{NAME}` again.")
        return
      end

      GithubActionsGenerator.start
    end

    private

    def existing_files
      @existing_files ||= GENERATED_FILES.select { |path| File.exist?(path) }
    end
  end
end
