# frozen_string_literal: true

require "spec_helper"
require "pathname"
require "tmpdir"
require "yaml"

describe Command::GenerateGithubActions, :enable_validations, :without_config_file do
  def build_action_path
    playground.join(".github/actions/cpflow-build-docker-image/action.yml")
  end

  def review_app_workflow_path
    playground.join(".github/workflows/cpflow-deploy-review-app.yml")
  end

  def staging_workflow_path
    playground.join(".github/workflows/cpflow-deploy-staging.yml")
  end

  def delete_review_workflow_path
    playground.join(".github/workflows/cpflow-delete-review-app.yml")
  end

  def help_workflow_path
    playground.join(".github/workflows/cpflow-help-command.yml")
  end

  def promote_workflow_path
    playground.join(".github/workflows/cpflow-promote-staging-to-production.yml")
  end

  def setup_action_path
    playground.join(".github/actions/cpflow-setup-environment/action.yml")
  end

  def delete_app_script_path
    playground.join(".github/actions/cpflow-delete-control-plane-app/delete-app.sh")
  end

  def generated_yaml_paths
    Dir.glob(playground.join(".github/**/*.yml")).sort
  end

  let(:playground) { Pathname.new(Dir.mktmpdir("cpflow-github-actions")) }

  after do
    FileUtils.remove_entry(playground.to_s) if playground.exist?
  end

  context "when the cpflow GitHub Actions files do not exist yet" do
    before do
      inside_dir(playground) do
        Cpflow::Cli.start([described_class::NAME])
      end
    end

    it "creates the expected workflow and action files" do
      expect(review_app_workflow_path).to exist
      expect(build_action_path).to exist
      expect(setup_action_path).to exist
      expect(delete_app_script_path).to exist
      expect(delete_app_script_path).to be_executable
    end

    it "substitutes the cpflow version placeholder" do
      expect(setup_action_path.read).to include(%(default: "#{Cpflow::VERSION}"))
    end

    it "exposes Docker build action inputs" do
      contents = build_action_path.read
      expect(contents).to include("docker_build_extra_args:")
      expect(contents).to include("docker_build_ssh_key:")
      expect(contents).to include("docker_build_ssh_known_hosts:")
    end

    it "documents the docker_build_extra_args usage and validates tokens" do
      contents = build_action_path.read
      expect(contents).to include("--build-arg=FOO=bar")
      expect(contents).to include('docker_build_args+=("--ssh=default")')
      expect(contents).to include(
        "docker_build_extra_args entries must be single docker-build tokens."
      )
    end

    it "pins the default SSH known_hosts entries without ssh-keyscan" do
      contents = build_action_path.read
      expect(contents).to include('printf \'%s\n\' "${DOCKER_BUILD_SSH_KNOWN_HOSTS}"')
      expect(contents).not_to include("ssh-keyscan")
      expect(contents).to include("github.com ssh-ed25519")
    end

    it "wires Docker build inputs through the review-app workflow" do
      contents = review_app_workflow_path.read
      expect(contents).to include("docker_build_extra_args: ${{ vars.DOCKER_BUILD_EXTRA_ARGS }}")
      expect(contents).to include("docker_build_ssh_key: ${{ secrets.DOCKER_BUILD_SSH_KEY }}")
      expect(contents).to include(
        "docker_build_ssh_known_hosts: ${{ vars.DOCKER_BUILD_SSH_KNOWN_HOSTS }}"
      )
    end

    it "gates review-app deploys by author_association and skips fork PRs" do
      contents = review_app_workflow_path.read
      expect(contents).to include("github.event.comment.author_association")
      expect(contents).to include("Review app deploys are skipped for fork pull requests.")
    end

    it "handles missing PR comment ids gracefully in the review-app workflow" do
      expect(review_app_workflow_path.read).to include(
        "Skipping PR comment update because no comment id was created."
      )
    end

    it "configures delete-review-app concurrency and handles missing comment ids" do
      contents = delete_review_workflow_path.read
      expect(contents).to include("concurrency:")
      expect(contents).to include(
        "Skipping delete status comment update because no comment id was created."
      )
    end

    it "wires the help workflow author_association gate and Docker build env" do
      contents = help_workflow_path.read
      expect(contents).to include("github.event.comment.author_association")
      expect(contents).to include("DOCKER_BUILD_EXTRA_ARGS")
      expect(contents).to include("DOCKER_BUILD_SSH_KNOWN_HOSTS")
    end

    it "wires Docker build inputs through the staging workflow" do
      contents = staging_workflow_path.read
      expect(contents).to include("docker_build_extra_args: ${{ vars.DOCKER_BUILD_EXTRA_ARGS }}")
      expect(contents).to include("docker_build_ssh_key: ${{ secrets.DOCKER_BUILD_SSH_KEY }}")
      expect(contents).to include(
        "docker_build_ssh_known_hosts: ${{ vars.DOCKER_BUILD_SSH_KNOWN_HOSTS }}"
      )
    end

    it "documents the branch-filter trade-off and sets staging concurrency/vars" do
      contents = staging_workflow_path.read
      expect(contents).to include("GitHub does not allow repository vars in branch filters")
      expect(contents).to include("cpflow-deploy-staging-${{ github.ref_name }}")
      expect(contents).to include("variable:STAGING_APP_NAME")
    end

    it "configures the promote workflow's concurrency, release tagging, and rollback guard" do
      contents = promote_workflow_path.read
      expect(contents).to include("group: cpflow-promote-staging-to-production")
      expect(contents).to include(
        'release_tag="production-${release_date}-${timestamp}-${GITHUB_RUN_ID}"'
      )
      expect(contents).to include(
        "failure() && steps.capture-current.outputs.rollback_state != '' && " \
        "steps.capture-current.outputs.rollback_state != '{}'"
      )
    end

    it "writes the delete-app script with the not-found guard message" do
      expect(delete_app_script_path.read).to include("⚠️ Application does not exist")
    end

    it "produces valid YAML for every generated workflow and action file" do
      generated_yaml_paths.each do |path|
        expect { YAML.load_file(path, aliases: true) }.not_to raise_error
      end
    end

    it "skips startup checks for the local-only GitHub Actions generator command" do
      expect(Cpflow::Cli).not_to have_received(:check_cpln_version)
      expect(Cpflow::Cli).not_to have_received(:check_cpflow_version)
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

  context "when the repository already has unrelated GitHub files" do
    before do
      playground.join(".github").mkpath
      playground.join(".github/existing.yml").write("version: __CPFLOW_VERSION__\n")
    end

    it "does not rewrite the pre-existing files" do
      inside_dir(playground) do
        Cpflow::Cli.start([described_class::NAME])

        expect(playground.join(".github/existing.yml").read).to eq("version: __CPFLOW_VERSION__\n")
      end
    end
  end
end
