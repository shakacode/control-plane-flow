# frozen_string_literal: true

require "spec_helper"
require "pathname"
require "tmpdir"

describe Command::GenerateGithubActions, :enable_validations, :without_config_file do
  def inside_dir(path)
    original_working_dir = Dir.pwd
    Dir.chdir(path)
    yield if block_given?
  ensure
    Dir.chdir(original_working_dir)
  end

  def build_action_path
    playground.join(".github/actions/cpflow-build-docker-image/action.yml")
  end

  def review_app_workflow_path
    playground.join(".github/workflows/cpflow-deploy-review-app.yml")
  end

  def staging_workflow_path
    playground.join(".github/workflows/cpflow-deploy-staging.yml")
  end

  def setup_action_path
    playground.join(".github/actions/cpflow-setup-environment/action.yml")
  end

  def delete_app_script_path
    playground.join(".github/actions/cpflow-delete-control-plane-app/delete-app.sh")
  end

  let(:playground) { Pathname.new(Dir.mktmpdir("cpflow-github-actions")) }

  after do
    FileUtils.remove_entry(playground.to_s) if playground.exist?
  end

  context "when the cpflow GitHub Actions files do not exist yet" do
    it "generates the reusable workflow and action files" do
      inside_dir(playground) do
        expect(review_app_workflow_path).not_to exist
        expect(build_action_path).not_to exist
        expect(setup_action_path).not_to exist

        Cpflow::Cli.start([described_class::NAME])

        expect(review_app_workflow_path).to exist
        expect(build_action_path).to exist
        expect(setup_action_path).to exist
        expect(delete_app_script_path).to exist
        expect(delete_app_script_path).to be_executable
        expect(setup_action_path.read).to include(%(default: "#{Cpflow::VERSION}"))
        expect(build_action_path.read).to include("docker_build_extra_args:")
        expect(build_action_path.read).to include("docker_build_ssh_key:")
        expect(build_action_path.read).to include('docker_build_args+=("--ssh default")')
        expect(review_app_workflow_path.read).to include("docker_build_extra_args: ${{ vars.DOCKER_BUILD_EXTRA_ARGS }}")
        expect(review_app_workflow_path.read).to include("docker_build_ssh_key: ${{ secrets.DOCKER_BUILD_SSH_KEY }}")
        expect(review_app_workflow_path.read).to include("github.event.comment.author_association")
        expect(review_app_workflow_path.read).to include("Review app deploys are skipped for fork pull requests.")
        expect(staging_workflow_path.read).to include("docker_build_extra_args: ${{ vars.DOCKER_BUILD_EXTRA_ARGS }}")
        expect(staging_workflow_path.read).to include("docker_build_ssh_key: ${{ secrets.DOCKER_BUILD_SSH_KEY }}")
        expect(staging_workflow_path.read).to include("cpflow-deploy-staging-${{ github.ref_name }}")
        expect(staging_workflow_path.read).to include("variable:STAGING_APP_NAME")
      end
    end
  end

  context "when one of the generated files already exists" do
    before do
      FileUtils.mkdir_p(review_app_workflow_path.dirname)
      review_app_workflow_path.write("existing-content\n")
    end

    it "warns and leaves the project untouched" do
      inside_dir(playground) do
        expect do
          Cpflow::Cli.start([described_class::NAME])
        end.to output(/already exist/).to_stderr

        expect(review_app_workflow_path.read).to eq("existing-content\n")
        expect(setup_action_path).not_to exist
      end
    end
  end
end
