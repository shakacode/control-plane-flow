# frozen_string_literal: true

require "spec_helper"
require "pathname"
require "tmpdir"

describe Command::UpdateGithubActions do
  let(:options) { {} }
  let(:config) { instance_double(Config, options: options) }
  let(:command) { described_class.new(config) }
  let(:playground) { Pathname.new(Dir.mktmpdir("cpflow-update-github-actions")) }

  before do
    allow(Command::GithubActionsGenerator).to receive(:start)
    allow(Shell).to receive(:info)
    allow(Shell).to receive(:warn)
  end

  after do
    FileUtils.remove_entry(playground.to_s) if playground.exist?
  end

  def call_inside_playground
    inside_dir(playground) do
      command.call
    end
  end

  def write_generated_file(relative_path, contents)
    path = playground.join(relative_path)
    FileUtils.mkdir_p(path.dirname)
    File.write(path, contents)
  end

  def write_staging_workflow(branches)
    branch_lines = branches.map { |branch| "      - #{branch}" }.join("\n")
    write_generated_file(".github/workflows/cpflow-deploy-staging.yml", <<~YAML)
      name: Deploy staging
      on:
        push:
          branches:
      #{branch_lines}
    YAML
  end

  context "when no generated files exist" do
    it "aborts with instructions to generate the files first" do
      allow(Shell).to receive(:abort).and_raise(SystemExit.new(ExitCode::ERROR_DEFAULT))

      expect { call_inside_playground }.to raise_error(SystemExit)

      expect(Shell).to have_received(:abort).with(/No generated cpflow GitHub Actions files found/)
      expect(Command::GithubActionsGenerator).not_to have_received(:start)
    end
  end

  context "when --staging-branch is given" do
    let(:options) { { staging_branch: "develop" } }

    it "regenerates with the explicit staging branch" do
      write_staging_workflow(%w[main master])

      call_inside_playground

      expect(Command::GithubActionsGenerator).to have_received(:start).with(["develop"])
    end

    it "prints the post-update message" do
      write_staging_workflow(%w[main master])

      call_inside_playground

      expect(Shell).to have_received(:info).with(/Updated cpflow GitHub Actions wrappers for cpflow #{Cpflow::VERSION}/)
    end
  end

  context "when --staging-branch is invalid" do
    let(:options) { { staging_branch: "bad..branch" } }

    it "aborts without regenerating" do
      allow(Shell).to receive(:abort).and_raise(SystemExit.new(ExitCode::ERROR_DEFAULT))
      write_staging_workflow(%w[main master])

      expect { call_inside_playground }.to raise_error(SystemExit)

      expect(Shell).to have_received(:abort).with(/Invalid --staging-branch value/)
      expect(Command::GithubActionsGenerator).not_to have_received(:start)
    end
  end

  context "when the existing staging workflow uses the default branches" do
    it "regenerates without an explicit staging branch" do
      write_staging_workflow(%w[main master])

      call_inside_playground

      expect(Command::GithubActionsGenerator).to have_received(:start).with([])
    end
  end

  context "when the existing staging workflow uses a single custom branch" do
    it "preserves the custom staging branch" do
      write_staging_workflow(%w[develop])

      call_inside_playground

      expect(Command::GithubActionsGenerator).to have_received(:start).with(["develop"])
    end

    it "reads workflows whose on key is parsed as a string" do
      write_generated_file(".github/workflows/cpflow-deploy-staging.yml", <<~YAML)
        name: Deploy staging
        "on":
          push:
            branches:
              - develop
      YAML

      call_inside_playground

      expect(Command::GithubActionsGenerator).to have_received(:start).with(["develop"])
    end
  end

  context "when the existing staging workflow uses multiple custom branches" do
    it "warns and regenerates with the default branches" do
      write_staging_workflow(%w[develop hotfix])

      call_inside_playground

      expect(Shell).to have_received(:warn).with(/multiple custom push branches: develop, hotfix/)
      expect(Command::GithubActionsGenerator).to have_received(:start).with([])
    end
  end

  context "when the staging workflow is missing but other generated files exist" do
    it "regenerates without an explicit staging branch" do
      write_generated_file(".github/cpflow-help.md", "# help\n")

      call_inside_playground

      expect(Command::GithubActionsGenerator).to have_received(:start).with([])
    end
  end

  context "when the staging workflow cannot be parsed" do
    it "warns and regenerates with the default branches" do
      write_generated_file(".github/workflows/cpflow-deploy-staging.yml", "on: [unbalanced\n")

      call_inside_playground

      expect(Shell).to have_received(:warn).with(/Could not parse/)
      expect(Command::GithubActionsGenerator).to have_received(:start).with([])
    end
  end

  context "when the staging workflow is not a mapping" do
    it "regenerates with the default branches" do
      write_generated_file(".github/workflows/cpflow-deploy-staging.yml", "- just\n- a\n- list\n")

      call_inside_playground

      expect(Command::GithubActionsGenerator).to have_received(:start).with([])
    end
  end
end
