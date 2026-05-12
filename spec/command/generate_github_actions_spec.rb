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

  def cleanup_stale_review_apps_workflow_path
    playground.join(".github/workflows/cpflow-cleanup-stale-review-apps.yml")
  end

  def help_workflow_path
    playground.join(".github/workflows/cpflow-help-command.yml")
  end

  def pr_open_help_workflow_path
    playground.join(".github/workflows/cpflow-review-app-help.yml")
  end

  def promote_workflow_path
    playground.join(".github/workflows/cpflow-promote-staging-to-production.yml")
  end

  def setup_action_path
    playground.join(".github/actions/cpflow-setup-environment/action.yml")
  end

  def detect_release_action_path
    playground.join(".github/actions/cpflow-detect-release-phase/action.yml")
  end

  def wait_for_health_action_path
    playground.join(".github/actions/cpflow-wait-for-health/action.yml")
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
      expect(setup_action_path.read).to include(%(default_cpflow_version="#{Cpflow::VERSION}"))
    end

    it "exposes overridable cpflow and cpln-cli version inputs" do
      contents = setup_action_path.read
      expect(contents).to include("cpln_cli_version:")
      expect(contents).to include('default_cpln_cli_version="3.3.1"')
      expect(staging_workflow_path.read).to include("cpln_cli_version: ${{ vars.CPLN_CLI_VERSION }}")
      expect(staging_workflow_path.read).to include("cpflow_version: ${{ vars.CPFLOW_VERSION }}")
    end

    it "passes setup action versions through env before using them in shell commands" do
      contents = setup_action_path.read

      expect(contents).to include("CPLN_CLI_VERSION: ${{ inputs.cpln_cli_version }}")
      expect(contents).to include("CPFLOW_VERSION: ${{ inputs.cpflow_version }}")
      expect(contents).to include('npm_global_prefix="${HOME}/.npm-global"')
      expect(contents).to include('echo "${npm_global_prefix}/bin" >> "$GITHUB_PATH"')
      expect(contents).to include(
        'npm install --global --prefix "${npm_global_prefix}" "@controlplane/cli@${CPLN_CLI_VERSION}"'
      )
      expect(contents).not_to include("sudo npm install")
      expect(contents).to include('gem install cpflow -v "${CPFLOW_VERSION}" --no-document')
      expect(contents).not_to include(
        "npm install -g @controlplane/cli@${{ inputs.cpln_cli_version }}"
      )
      expect(contents).not_to include("gem install cpflow -v ${{ inputs.cpflow_version }}")
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

    it "registers SSH key cleanup before validating extra Docker build args" do
      contents = build_action_path.read

      expect(contents).to include("cleanup_build_ssh()")
      expect(contents.index("cleanup_build_ssh()")).to be < contents.index("trap cleanup_build_ssh EXIT")
      expect(contents.index("trap cleanup_build_ssh EXIT")).to be < contents.index('cd "${WORKING_DIRECTORY}"')
      expect(contents.index("trap cleanup_build_ssh EXIT")).to be < contents.index(
        'if [[ -n "${DOCKER_BUILD_EXTRA_ARGS}" ]]'
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
      expect(contents).to include("Review app deploys from fork pull requests require a branch")
      expect(contents).to include('echo "allowed=false" >> "$GITHUB_OUTPUT"')
    end

    it "keeps trusted generated actions separate from PR-controlled app code" do
      contents = review_app_workflow_path.read

      expect(contents).to include("ref: ${{ github.event.repository.default_branch }}")
      expect(contents).to include("path: app")
      expect(contents).to include("persist-credentials: false")
      expect(contents).to include("rm -rf app/.git")
      expect(contents).to include("working-directory: app")
      expect(contents).to include("working_directory: app")
    end

    it "passes GitHub event metadata through shell env vars instead of inline expressions" do
      contents = review_app_workflow_path.read

      expect(contents).to include("EVENT_NAME: ${{ github.event_name }}")
      expect(contents).not_to include('case "${{ github.event_name }}"')
      expect(contents).not_to include('[[ "${{ github.event_name }}"')
    end

    it "distinguishes review-app not-found from cpflow exists errors" do
      contents = review_app_workflow_path.read

      expect(contents).to include("exists_status")
      expect(contents).to include("            3)")
      expect(contents).to include('echo "exists=false" >> "$GITHUB_OUTPUT"')
      expect(contents).to include("cpflow exists returned unexpected exit code")
    end

    it "documents that review app deployments bypass required branch-protection contexts" do
      expect(review_app_workflow_path.read).to include(
        "required_contexts: [], // intentional: review apps deploy regardless of required status checks"
      )
    end

    it "handles missing PR comment ids gracefully in the review-app workflow" do
      expect(review_app_workflow_path.read).to include(
        "Skipping PR comment update because no comment id was created."
      )
    end

    it "configures delete-review-app concurrency and handles missing comment ids" do
      contents = delete_review_workflow_path.read
      expect(contents).to include("concurrency:")
      expect(contents).to include('pull_request_friendly: "true"')
      expect(contents).to include("pull_request_target is intentional")
      expect(contents).to include("does not set `ref:`")
      expect(contents).to include(
        "Skipping delete status comment update because no comment id was created."
      )
    end

    it "uses shell env vars for stale review cleanup inputs" do
      contents = cleanup_stale_review_apps_workflow_path.read

      expect(contents).to include("REVIEW_APP_PREFIX: ${{ vars.REVIEW_APP_PREFIX }}")
      expect(contents).to include("CPLN_ORG_STAGING: ${{ vars.CPLN_ORG_STAGING }}")
      expect(contents).to include('cpflow cleanup-stale-apps -a "${REVIEW_APP_PREFIX}"')
      expect(contents).not_to include('cpflow cleanup-stale-apps -a "${{ vars.REVIEW_APP_PREFIX }}"')
      expect(contents).to include("persist-credentials: false")
    end

    it "wires the help workflow author_association gate" do
      contents = help_workflow_path.read
      expect(contents).to include("github.event.comment.author_association")
      expect(contents).to include("contents: read")
      expect(contents).to include('fs.readFileSync(".github/cpflow-help.md"')
    end

    it "pins the +review-app-* workflow trigger strings" do
      expect(review_app_workflow_path.read).to include("github.event.comment.body == '+review-app-deploy'")
      expect(delete_review_workflow_path.read).to include("github.event.comment.body == '+review-app-delete'")
      expect(help_workflow_path.read).to include("github.event.comment.body == '+review-app-help'")
    end

    it "pins the +review-app-* commands in the PR-open message" do
      pr_open_help = pr_open_help_workflow_path.read

      expect(pr_open_help).to include('"Repo owners, members, and collaborators can use these commands:"')
      # The leading " is the opening quote of the JS array string literal in cpflow-review-app-help.yml.
      expect(pr_open_help).to include('"- `+review-app-deploy`')
      expect(pr_open_help).to include('"- `+review-app-delete`')
      expect(pr_open_help).to include('"- `+review-app-help`')
      expect(pr_open_help).to include(
        '"For setup details, repo owners, members, and collaborators can comment `+review-app-help`."'
      )
    end

    it "pins the +review-app-* commands in the long-form help markdown" do
      help_md = playground.join(".github/cpflow-help.md").read

      expect(help_md).to include("`+review-app-deploy`")
      expect(help_md).to include("`+review-app-delete`")
      expect(help_md).to include("`+review-app-help`")
    end

    it "documents Docker build vars in the help markdown" do
      help_md_path = playground.join(".github/cpflow-help.md")
      contents = help_md_path.read
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

    it "does not persist checkout credentials in staging jobs" do
      expect(staging_workflow_path.read.scan("persist-credentials: false").length).to eq(2)
    end

    it "documents the branch-filter trade-off and sets staging concurrency/vars" do
      contents = staging_workflow_path.read
      expect(contents).to include("GitHub does not allow repository vars in branch filters")
      expect(contents).to include('branches: ["main", "master"]')
      expect(contents).to include("STAGING_APP_BRANCH: ${{ vars.STAGING_APP_BRANCH }}")
      expect(contents).to include("cpflow-deploy-staging-${{ github.ref_name }}")
      expect(contents).to include("variable:STAGING_APP_NAME")
    end

    it "configures the promote workflow's concurrency, release tagging, and rollback guard" do
      contents = promote_workflow_path.read
      expect(contents).to include("group: cpflow-promote-staging-to-production")
      expect(contents).to include("contents: read")
      expect(contents).to include("create-github-release:")
      expect(contents).to include("contents: write")
      expect(contents).to include("GH_REPO: ${{ github.repository }}")
      expect(contents).to include("Production-only variables")
      expect(contents).to include("map({name, image})")
      expect(contents).to include("Could not retrieve current containers")
      expect(contents).to include("Could not parse rollback state")
      expect(contents).to include("Could not parse captured containers")
      expect(contents).to include("Could not build rollback image list")
      expect(contents).to include("Container set changed")
      expect(contents).to include("index($container.name)")
      expect(contents).to include(
        'release_tag="production-${release_date}-${timestamp}-${GITHUB_RUN_ID}"'
      )
      expect(contents).to include(
        "failure() && steps.capture-current.outputs.rollback_state != '' && " \
        "steps.capture-current.outputs.rollback_state != '{}'"
      )
    end

    it "does not persist checkout credentials in the production promotion job" do
      expect(promote_workflow_path.read.scan("persist-credentials: false").length).to eq(1)
    end

    it "copies the image currently deployed on staging instead of the newest pushed staging image" do
      contents = promote_workflow_path.read

      expect(contents).to include("id: staging-image")
      expect(contents).to include('CPLN_TOKEN="${CPLN_TOKEN_STAGING}" cpln workload get')
      expect(contents).to include("staging_image=\"${staging_image_ref##*/image/}\"")
      expect(contents).to include("STAGING_IMAGE: ${{ steps.staging-image.outputs.image }}")
      expect(contents).to include('cpflow copy-image-from-upstream -a "${PRODUCTION_APP_NAME}" ' \
                                  '--org "${CPLN_ORG_PRODUCTION}" --image "${STAGING_IMAGE}"')
    end

    it "detects release phase support from controlplane.yml instead of cpflow config text" do
      contents = detect_release_action_path.read

      expect(contents).to include('YAML.safe_load(File.read(".controlplane/controlplane.yml"), aliases: true)')
      expect(contents).to include("app_name.start_with?(name)")
      expect(contents).not_to include("cpflow config")
      expect(contents).not_to include("grep -qE")
    end

    it "makes pull_request_target config validation skip cleanly when setup is incomplete" do
      contents = playground.join(".github/actions/cpflow-validate-config/action.yml").read

      expect(contents).to include('pull_request_target"')
      expect(contents).to include('echo "ready=false" >> "$GITHUB_OUTPUT"')
    end

    it "reports a missing primary workload before polling health" do
      contents = wait_for_health_action_path.read

      expect(contents).to include("Workload '${CPFLOW_WORKLOAD_NAME}' not found")
      expect(contents).to include("Set PRIMARY_WORKLOAD to the correct workload name.")
      expect(contents).to include("has no endpoint yet; waiting for one to be assigned")
    end

    it "writes the delete-app script with the not-found guard message" do
      contents = delete_app_script_path.read

      expect(contents).to include("⚠️ Application does not exist")
      expect(contents).to include("exists_status")
      expect(contents).to include("  3)")
      expect(contents).to include("failed to determine whether application exists")
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

    # Snapshot guard: every generated file must equal its template with the documented
    # substitutions applied. This catches drift when the generator silently mutates
    # output (e.g. a refactor introduces an unintended transform) and forces template
    # changes to be reviewed line-by-line in the diff rather than relying on individual
    # `expect(...).to include(...)` assertions to remember every load-bearing line.
    it "emits files identical to their templates with default substitutions applied" do
      template_root = Cpflow.root_path.join("lib/github_flow_templates")
      relative_paths = described_class.generated_files

      expect(relative_paths).not_to be_empty

      relative_paths.each do |relative_path|
        template = template_root.join(relative_path).read
        expected = template
                   .gsub("__CPFLOW_VERSION__", Cpflow::VERSION)
                   .gsub("__STAGING_BRANCH_FILTER__", %("main", "master"))
                   .gsub("__STAGING_APP_BRANCH_EXPRESSION__", "${{ vars.STAGING_APP_BRANCH }}")
        actual = playground.join(relative_path).read

        expect(actual).to eq(expected), "Drift in generated #{relative_path}"
      end
    end

    it "generates exactly the templated file set (catches accidental additions/removals)" do
      template_root = Cpflow.root_path.join("lib/github_flow_templates")
      expected = Dir.glob(template_root.join("**", "*").to_s, File::FNM_DOTMATCH)
                    .select { |path| File.file?(path) }
                    .map { |path| Pathname.new(path).relative_path_from(template_root).to_s }
                    .sort

      generated = Dir.glob(playground.join(".github/**/*").to_s, File::FNM_DOTMATCH)
                     .select { |path| File.file?(path) }
                     .map { |path| Pathname.new(path).relative_path_from(playground).to_s }
                     .sort

      expect(generated).to eq(expected)
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

  context "when a custom staging branch is provided" do
    before do
      inside_dir(playground) do
        Cpflow::Cli.start([described_class::NAME, "--staging-branch", "release@2025"])
      end
    end

    it "bakes that branch into the staging trigger and default branch check" do
      contents = staging_workflow_path.read

      expect(contents).to include('branches: ["release@2025"]')
      expect(contents).to include("vars.STAGING_APP_BRANCH || 'release@2025'")
    end
  end

  context "when a custom staging branch has unsafe characters" do
    it "aborts before generating files" do
      inside_dir(playground) do
        result = run_cpflow_command(described_class::NAME, "--staging-branch", "develop bad")

        expect(result[:status]).to eq(ExitCode::ERROR_DEFAULT)
        expect(result[:stderr]).to include("Invalid --staging-branch value")
        expect(playground.join(".github")).not_to exist
      end
    end

    it "rejects invalid git branch syntax" do
      inside_dir(playground) do
        result = run_cpflow_command(described_class::NAME, "--staging-branch", "feature..bad")

        expect(result[:status]).to eq(ExitCode::ERROR_DEFAULT)
        expect(result[:stderr]).to include("valid git branch name")
        expect(playground.join(".github")).not_to exist
      end
    end

    it "rejects forbidden git ref sequences" do
      inside_dir(playground) do
        result = run_cpflow_command(described_class::NAME, "--staging-branch", "feature@{bad")

        expect(result[:status]).to eq(ExitCode::ERROR_DEFAULT)
        expect(result[:stderr]).to include("valid git branch name")
        expect(playground.join(".github")).not_to exist
      end
    end
  end
end
