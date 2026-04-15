# frozen_string_literal: true

module Command
  class GithubActionsGenerator < Thor::Group
    include Thor::Actions
    TEMPLATE_VARIABLES = {
      "__CPFLOW_VERSION__" => Cpflow::VERSION
    }.freeze

    def copy_files
      directory("github_flow_templates", ".", verbose: ENV.fetch("HIDE_COMMAND_OUTPUT", nil) != "true")
      substitute_template_variables(".github")
      make_shell_scripts_executable(".github")
    end

    def self.source_root
      Cpflow.root_path.join("lib")
    end

    private

    def substitute_template_variables(root_path)
      Dir.glob(File.join(root_path, "**/*")).each do |path|
        next unless File.file?(path)

        contents = File.read(path)
        updated_contents = TEMPLATE_VARIABLES.reduce(contents) do |memo, (placeholder, value)|
          memo.gsub(placeholder, value)
        end

        next if updated_contents == contents

        File.write(path, updated_contents)
      end
    end

    def make_shell_scripts_executable(root_path)
      Dir.glob(File.join(root_path, "**/*.sh")).each do |path|
        next unless File.file?(path)

        FileUtils.chmod(0o755, path)
      end
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
      GENERATED_FILES.select { |path| File.exist?(path) }
    end
  end
end
