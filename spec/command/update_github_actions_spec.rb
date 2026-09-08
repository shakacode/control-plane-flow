# frozen_string_literal: true

require "spec_helper"
require "pathname"
require "tmpdir"

describe Command::UpdateGithubActions do
  let(:options) { { workflows: ["cpflow-deploy-staging.yml"] } }
  let(:config) { instance_double(Config, options: options) }
  let(:command) { described_class.new(config) }
  let(:playground) { Pathname.new(Dir.mktmpdir("cpflow-update-github-actions")) }

  before do
    allow(Command::GithubActionsGenerator).to receive(:new).and_return(instance_double(Command::GithubActionsGenerator,
                                                                                       invoke_all: nil))
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
      expect(Command::GithubActionsGenerator).not_to have_received(:new)
    end
  end

  it "preserves every workflow by default even when staging YAML is malformed" do
    options[:workflows] = []
    write_generated_file(".github/workflows/cpflow-deploy-staging.yml", "on: [unbalanced\n")

    call_inside_playground

    expect(Command::GithubActionsGenerator).to have_received(:new).with([], workflows: [])
  end

  it "refuses to overwrite a legacy customized validator before any writes" do
    allow(Shell).to receive(:abort).and_raise(SystemExit.new(ExitCode::ERROR_DEFAULT))
    options[:workflows] = []
    write_generated_file("bin/test-cpflow-github-flow", "#!/bin/bash\n# HiChee custom checks\nexit 42\n")

    expect { call_inside_playground }.to raise_error(SystemExit)
    expect(Shell).to have_received(:abort).with(%r{bin/test-cpflow-github-flow-custom})
    expect(Command::GithubActionsGenerator).not_to have_received(:new)
  end

  context "when --staging-branch is given" do
    let(:options) { { staging_branch: "develop", workflows: ["cpflow-deploy-staging.yml"] } }

    it "regenerates with the explicit staging branch" do
      write_staging_workflow(%w[main master])

      call_inside_playground

      expect(Command::GithubActionsGenerator).to have_received(:new).with(["develop"],
                                                                          workflows: ["cpflow-deploy-staging.yml"])
    end

    it "prints the post-update message" do
      write_staging_workflow(%w[main master])

      call_inside_playground

      expect(Shell).to have_received(:info).with(/Updated cpflow GitHub Actions files for cpflow #{Cpflow::VERSION}/)
    end
  end

  it "rejects unknown workflow names before any writes" do
    allow(Shell).to receive(:abort).and_raise(SystemExit)
    options[:workflows] = ["cpflow-typo.yml"]
    write_staging_workflow(%w[main master])

    expect { call_inside_playground }.to raise_error(SystemExit)
    expect(Shell).to have_received(:abort).with(/Unknown --workflows/)
    expect(Command::GithubActionsGenerator).not_to have_received(:new)
  end

  it "requires staging workflow selection to change its branch" do
    allow(Shell).to receive(:abort).and_raise(SystemExit)
    options.merge!(workflows: [], staging_branch: "develop")
    write_staging_workflow(%w[main master])

    expect { call_inside_playground }.to raise_error(SystemExit)
    expect(Shell).to have_received(:abort).with(/--staging-branch requires --workflows/)
    expect(Command::GithubActionsGenerator).not_to have_received(:new)
  end

  it "requires an explicit branch when adding staging" do
    allow(Shell).to receive(:abort).and_raise(SystemExit)
    write_generated_file(".github/actions/cpflow-setup-environment/action.yml", "name: Existing action\n")

    expect { call_inside_playground }.to raise_error(SystemExit)
    expect(Shell).to have_received(:abort).with(/--staging-branch BRANCH/)
    expect(Command::GithubActionsGenerator).not_to have_received(:new)
  end

  context "when --staging-branch is invalid" do
    let(:options) { { staging_branch: "bad..branch", workflows: ["cpflow-deploy-staging.yml"] } }

    it "aborts without regenerating" do
      allow(Shell).to receive(:abort).and_raise(SystemExit.new(ExitCode::ERROR_DEFAULT))
      write_staging_workflow(%w[main master])

      expect { call_inside_playground }.to raise_error(SystemExit)

      expect(Shell).to have_received(:abort).with(/Invalid --staging-branch value/)
      expect(Command::GithubActionsGenerator).not_to have_received(:new)
    end
  end

  context "when the existing staging workflow uses the default branches" do
    it "regenerates without an explicit staging branch" do
      write_staging_workflow(%w[main master])

      call_inside_playground

      expect(Command::GithubActionsGenerator).to have_received(:new).with([], workflows: ["cpflow-deploy-staging.yml"])
    end
  end

  context "when the existing staging workflow uses a single custom branch" do
    it "preserves the custom staging branch" do
      write_staging_workflow(%w[develop])

      call_inside_playground

      expect(Command::GithubActionsGenerator).to have_received(:new).with(["develop"],
                                                                          workflows: ["cpflow-deploy-staging.yml"])
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

      expect(Command::GithubActionsGenerator).to have_received(:new).with(["develop"],
                                                                          workflows: ["cpflow-deploy-staging.yml"])
    end
  end

  context "when the existing staging workflow uses multiple custom branches" do
    it "rejects ambiguous branches before regenerating" do
      allow(Shell).to receive(:abort).and_raise(SystemExit)
      write_staging_workflow(%w[develop hotfix])

      expect { call_inside_playground }.to raise_error(SystemExit)
      expect(Command::GithubActionsGenerator).not_to have_received(:new)
    end
  end

  context "when the staging workflow is missing but other generated files exist" do
    it "regenerates when only a generated local action exists" do
      options[:workflows] = []
      write_generated_file(".github/actions/cpflow-setup-environment/action.yml", "name: Existing action\n")

      call_inside_playground

      expect(Command::GithubActionsGenerator).to have_received(:new).with([], workflows: [])
    end
  end

  context "when the staging workflow cannot be parsed" do
    it "rejects malformed staging before regenerating" do
      allow(Shell).to receive(:abort).and_raise(SystemExit)
      write_generated_file(".github/workflows/cpflow-deploy-staging.yml", "on: [unbalanced\n")

      expect { call_inside_playground }.to raise_error(SystemExit)

      expect(Shell).to have_received(:abort).with(/Could not parse/)
      expect(Command::GithubActionsGenerator).not_to have_received(:new)
    end
  end

  context "when the staging workflow is not a mapping" do
    it "rejects missing branch evidence before regenerating" do
      allow(Shell).to receive(:abort).and_raise(SystemExit)
      write_generated_file(".github/workflows/cpflow-deploy-staging.yml", "- just\n- a\n- list\n")

      expect { call_inside_playground }.to raise_error(SystemExit)

      expect(Command::GithubActionsGenerator).not_to have_received(:new)
    end
  end
end
