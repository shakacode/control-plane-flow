# frozen_string_literal: true

require "spec_helper"
require "pathname"
require "tmpdir"

describe Command::AiGithubFlowPrompt, :enable_validations, :without_config_file do
  def inside_dir(path)
    original_working_dir = Dir.pwd
    Dir.chdir(path)
    yield if block_given?
  ensure
    Dir.chdir(original_working_dir)
  end

  let(:playground) { Pathname.new(Dir.mktmpdir("cpflow-ai-github-flow-prompt")) }

  after do
    FileUtils.remove_entry(playground.to_s) if playground.exist?
  end

  it "prints the AI rollout prompt with the inferred repo-name app prefix" do
    inside_dir(playground.join("sample-project").tap(&:mkpath)) do
      result = run_cpflow_command(described_class::NAME)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("repo-name default (`sample-project`)")
      expect(result[:stdout]).to include("cpflow generate-github-actions")
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
