# frozen_string_literal: true

require_relative "../core/repo_introspection"

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

    # The prompt lives in its own file with one instruction per bullet, so a person can read it and
    # a change shows as a small diff. docs/ai-github-flow-prompt.md carries the same text with no app
    # prefix; a spec keeps the two equal.
    PROMPT_PATH = File.expand_path("ai_github_flow_prompt.txt", __dir__)

    def self.text(app_prefix: nil)
      format(File.read(PROMPT_PATH), prefix_note: app_prefix ? " (`#{app_prefix}`)" : "")
    end

    def call
      puts self.class.text(app_prefix: inferred_app_prefix)
    end

    private

    def inferred_app_prefix
      RepoIntrospection.inferred_app_prefix(Dir.pwd)
    end
  end
end
