# frozen_string_literal: true

require "spec_helper"
require "pathname"
require "tmpdir"

describe Command::GithubFlowReadiness, :enable_validations, :without_config_file do
  let(:playground) { Pathname.new(Dir.mktmpdir("cpflow-github-flow-readiness")) }

  after do
    FileUtils.remove_entry(playground.to_s) if playground.exist?
  end

  it "passes for a modern repo when exact gem and npm pins are available" do
    service = instance_double(GithubFlowReadinessService)
    allow(GithubFlowReadinessService).to receive(:new).and_return(service)
    allow(service).to receive_messages(
      results: [
        GithubFlowReadinessService::Result.new(status: :pass, message: "Ruby 3.3.7 is modern enough for rollout."),
        GithubFlowReadinessService::Result.new(
          status: :pass,
          message: "Checked 1 exact-pinned direct Ruby gem; all appear available on RubyGems."
        ),
        GithubFlowReadinessService::Result.new(
          status: :pass,
          message: "Checked 1 exact-pinned direct npm package; all appear available on npm."
        )
      ],
      summary: "No blocking readiness issues detected. Validate the real production build path before merging.",
      blockers?: false
    )

    inside_dir(playground) do
      result = run_cpflow_command(described_class::NAME)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("[PASS] Ruby 3.3.7 is modern enough for rollout.")
      expect(result[:stdout]).to include("No blocking readiness issues detected.")
    end
  end

  it "fails when the repo has rollout blockers" do
    service = instance_double(GithubFlowReadinessService)
    allow(GithubFlowReadinessService).to receive(:new).and_return(service)
    allow(service).to receive_messages(
      results: [
        GithubFlowReadinessService::Result.new(
          status: :fail,
          message: "Ruby 2.5.1 is legacy. Upgrade the repo toolchain before adding the GitHub flow."
        ),
        GithubFlowReadinessService::Result.new(
          status: :fail,
          message: "Direct npm package versions not available on npm: `react-on-rails-rsc@16.4.0`."
        )
      ],
      summary: "Blockers found. Fix them before generating the Control Plane GitHub flow.",
      blockers?: true
    )

    inside_dir(playground) do
      result = run_cpflow_command(described_class::NAME)

      expect(result[:status]).to eq(ExitCode::ERROR_DEFAULT)
      expect(result[:stdout]).to include("Ruby 2.5.1 is legacy")
      expect(result[:stdout]).to include("react-on-rails-rsc@16.4.0")
      expect(result[:stdout]).to include("Blockers found.")
    end
  end

  it "skips startup checks for the local-only readiness command" do
    service = instance_double(GithubFlowReadinessService, results: [], summary: "ok", blockers?: false)
    allow(GithubFlowReadinessService).to receive(:new).and_return(service)

    inside_dir(playground) do
      result = run_cpflow_command(described_class::NAME)

      expect(result[:status]).to eq(0)
      expect(Cpflow::Cli).not_to have_received(:check_cpln_version)
      expect(Cpflow::Cli).not_to have_received(:check_cpflow_version)
    end
  end
end
