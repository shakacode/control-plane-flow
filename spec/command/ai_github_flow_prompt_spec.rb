# frozen_string_literal: true

require "spec_helper"
require "pathname"
require "tmpdir"

describe Command::AiGithubFlowPrompt, :enable_validations, :without_config_file do
  let(:playground) { Pathname.new(Dir.mktmpdir("cpflow-ai-github-flow-prompt")) }

  after do
    FileUtils.remove_entry(playground.to_s) if playground.exist?
  end

  it "prints the AI rollout prompt with the inferred repo-name app prefix" do
    inside_dir(playground.join("sample-project").tap(&:mkpath)) do
      result = run_cpflow_command(described_class::NAME)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("cpflow github-flow-readiness")
      expect(result[:stdout]).to include("repo-name default (`sample-project`)")
      expect(result[:stdout]).to include("cpflow generate-github-actions")
      expect(result[:stdout]).to include("Do not hand-edit duplicated upstream refs")
      expect(result[:stdout]).to include("uses: ...@vX.Y.Z")
      expect(result[:stdout]).to include("cpflow setup-app --skip-post-creation-hook")
      expect(result[:stdout]).to include("cpflow apply-template")
      expect(result[:stdout]).to include("app secret policy")
      expect(result[:stdout]).to include("CPLN_TOKEN_PRODUCTION")
      expect(result[:stdout]).to include("monorepo without an already-decided single app boundary")
      expect(result[:stdout]).to include("DOCKER_BUILD_SSH_KNOWN_HOSTS")
      expect(result[:stdout]).to include("config/shakapacker.yml")
      expect(result[:stdout]).to include("config.auto_load_bundle = true")
      expect(result[:stdout]).to include("Only stop early for a real external blocker")
      expect(result[:stderr]).to be_empty
    end
  end

  it "skips startup checks for the local-only prompt command" do
    inside_dir(playground) do
      result = run_cpflow_command(described_class::NAME)

      expect(result[:status]).to eq(0)
      expect(Cpflow::Cli).not_to have_received(:check_cpln_version)
      expect(Cpflow::Cli).not_to have_received(:check_cpflow_version)
    end
  end
end
