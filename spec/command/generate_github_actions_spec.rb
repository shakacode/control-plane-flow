# frozen_string_literal: true

require "spec_helper"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

describe Command::GenerateGithubActions, :enable_validations, :without_config_file do
  def build_action_path
    shared_action_path("cpflow-build-docker-image")
  end

  def review_app_workflow_path
    playground.join(".github/workflows/cpflow-deploy-review-app.yml")
  end

  def reusable_review_app_workflow_path
    shared_workflow_path("cpflow-deploy-review-app")
  end

  def staging_workflow_path
    playground.join(".github/workflows/cpflow-deploy-staging.yml")
  end

  def reusable_staging_workflow_path
    shared_workflow_path("cpflow-deploy-staging")
  end

  def delete_review_workflow_path
    playground.join(".github/workflows/cpflow-delete-review-app.yml")
  end

  def reusable_delete_review_workflow_path
    shared_workflow_path("cpflow-delete-review-app")
  end

  def cleanup_stale_review_apps_workflow_path
    playground.join(".github/workflows/cpflow-cleanup-stale-review-apps.yml")
  end

  def reusable_cleanup_stale_review_apps_workflow_path
    shared_workflow_path("cpflow-cleanup-stale-review-apps")
  end

  def help_workflow_path
    playground.join(".github/workflows/cpflow-help-command.yml")
  end

  def reusable_help_workflow_path
    shared_workflow_path("cpflow-help-command")
  end

  def pr_open_help_workflow_path
    playground.join(".github/workflows/cpflow-review-app-help.yml")
  end

  def reusable_pr_open_help_workflow_path
    shared_workflow_path("cpflow-review-app-help")
  end

  def review_app_url_ruby_script
    match = reusable_review_app_workflow_path.read.match(
      /ruby -ruri -e '\n(?<script>.*?)\n\s*' "\$\{workload_name\}"/m
    )

    match[:script].lines.map { |line| line.delete_prefix("                  ") }.join
  end

  def run_review_app_url_script(**args)
    script_args = args.fetch_values(:workload_name, :workload_url, :app_domain_template, :app_name)
    stdout, stderr, status = Open3.capture3("ruby", "-ruri", "-e", review_app_url_ruby_script, *script_args)

    expect(stderr).to eq("")
    expect(status).to be_success
    stdout.strip
  end

  def command_body_match_expression(command)
    %(contains(fromJson('["#{command}","#{command}\\n","#{command}\\r\\n"]'), github.event.comment.body))
  end

  def promote_workflow_path
    playground.join(".github/workflows/cpflow-promote-staging-to-production.yml")
  end

  def reusable_promote_workflow_path
    shared_workflow_path("cpflow-promote-staging-to-production")
  end

  def setup_action_path
    shared_action_path("cpflow-setup-environment")
  end

  def pin_cpflow_ref_path
    playground.join("bin/pin-cpflow-github-ref")
  end

  def test_cpflow_flow_path
    playground.join("bin/test-cpflow-github-flow")
  end

  def detect_release_action_path
    shared_action_path("cpflow-detect-release-phase")
  end

  def wait_for_health_action_path
    shared_action_path("cpflow-wait-for-health")
  end

  def delete_app_script_path
    Cpflow.root_path.join(".github/actions/cpflow-delete-control-plane-app/delete-app.sh")
  end

  def generated_yaml_paths
    Dir.glob(playground.join(".github/**/*.yml"))
  end

  def shared_yaml_paths
    Dir.glob(Cpflow.root_path.join(".github/workflows/cpflow-*.yml").to_s) +
      Dir.glob(Cpflow.root_path.join(".github/actions/cpflow-*/*.yml").to_s)
  end

  def shared_action_path(name)
    Cpflow.root_path.join(".github/actions/#{name}/action.yml")
  end

  def shared_workflow_path(name)
    Cpflow.root_path.join(".github/workflows/#{name}.yml")
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
      expect(pin_cpflow_ref_path).to exist
      expect(test_cpflow_flow_path).to exist
      expect(delete_app_script_path).to exist
      expect(pin_cpflow_ref_path).to be_executable
      expect(test_cpflow_flow_path).to be_executable
      expect(delete_app_script_path).to be_executable
      expect(playground.join(".github/actions")).not_to exist
    end

    it "installs cpflow from the checked-out upstream repository by default" do
      contents = setup_action_path.read

      expect(contents).to include("CPFLOW_SOURCE_DIR: ${{ github.action_path }}/../../..")
      expect(contents).to include('cd "${cpflow_source_dir}"')
      expect(contents).to include('if [[ ! -f "${cpflow_source_dir}/cpflow.gemspec" ]]; then')
      expect(contents).to include("gem build cpflow.gemspec")
      expect(contents).to include('gem install "${cpflow_gem}" --no-document')
      expect(contents).to include(%q(trap 'rm -f "${cpflow_gem}"' EXIT))
      expect(contents).not_to include("default_cpflow_version")
    end

    it "exposes overridable cpflow and cpln-cli version inputs" do
      contents = setup_action_path.read
      expect(contents).to include("cpln_cli_version:")
      expect(contents).to include('default_cpln_cli_version="3.10.2"')
      expect(contents).to include("control_plane_flow_ref:")
      expect(reusable_staging_workflow_path.read).to include("cpln_cli_version: ${{ vars.CPLN_CLI_VERSION }}")
      expect(reusable_staging_workflow_path.read).to include("cpflow_version: ${{ vars.CPFLOW_VERSION }}")
    end

    # Issue #293: GitHub parses ${{ ... }} inside composite action `description:` fields
    # while loading the manifest, where `vars` is unavailable. Any literal expression
    # syntax there makes the entire action fail to load before workflow steps run.
    it "keeps GitHub expression syntax out of composite action metadata descriptions" do
      action_paths = Dir.glob(Cpflow.root_path.join(".github/actions/*/action.yml").to_s)
      expect(action_paths).not_to be_empty

      violations = action_paths.flat_map do |path|
        metadata = YAML.load_file(path, aliases: true)
        described = []
        described << ["description", metadata["description"]]
        (metadata["inputs"] || {}).each do |name, spec|
          described << ["inputs.#{name}.description", spec.is_a?(Hash) ? spec["description"] : nil]
        end
        (metadata["outputs"] || {}).each do |name, spec|
          described << ["outputs.#{name}.description", spec.is_a?(Hash) ? spec["description"] : nil]
        end
        described
          .select { |_key, value| value.is_a?(String) && value.include?("${{") }
          .map { |key, value| "#{path}: #{key} contains #{value.inspect}" }
      end

      expect(violations).to be_empty,
                            "Composite action descriptions must not embed GitHub expression syntax " \
                            "(see issue #293):\n#{violations.join("\n")}"
    end

    it "pins GitHub-owned actions to immutable Node 24-compatible releases" do
      contents = (generated_yaml_paths + shared_yaml_paths).map { |path| File.read(path) }.join("\n")

      expect(contents).to include("actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd")
      expect(contents).to include("actions/github-script@ed597411d8f924073f98dfc5c65a23a2325f34cd")
      expect(contents).not_to match(%r{actions/checkout@v\d+})
      expect(contents).not_to match(%r{actions/github-script@v\d+})
      expect(contents).not_to include("actions/checkout@v4")
      expect(contents).not_to include("actions/checkout@v5")
      expect(contents).not_to include("actions/github-script@v7")
    end

    it "generates thin reusable-workflow wrappers for non-production flows" do
      contents = review_app_workflow_path.read
      default_ref = "v#{Cpflow::VERSION}"

      expect(contents).to include(
        "uses: shakacode/control-plane-flow/.github/workflows/cpflow-deploy-review-app.yml@#{default_ref}"
      )
      expect(contents).not_to include("control_plane_flow_ref:")
      expect(contents).not_to include("Keep the @ref in `uses:`")
      expect(contents).to include("CPLN_TOKEN_STAGING: ${{ secrets.CPLN_TOKEN_STAGING }}")
      expect(contents).to include("DOCKER_BUILD_SSH_KEY: ${{ secrets.DOCKER_BUILD_SSH_KEY }}")
      expect(contents).not_to include("secrets: inherit")
      expect(contents).not_to include("Create initial PR comment")
      expect(contents).not_to include("Build Docker image")
      expect(contents).not_to include("Deploy to Control Plane")
    end

    it "updates existing generated wrappers to the installed cpflow release tag" do
      old_ref = "v5.0.0"
      current_ref = "v#{Cpflow::VERSION}"

      File.write(review_app_workflow_path, review_app_workflow_path.read.gsub(current_ref, old_ref))

      inside_dir(playground) do
        result = run_cpflow_command("update-github-actions")

        expect(result[:status]).to eq(0)
        expect(result[:stdout]).to include("Updated cpflow GitHub Actions wrappers for cpflow #{Cpflow::VERSION}.")
      end

      expect(review_app_workflow_path.read).to include(
        "uses: shakacode/control-plane-flow/.github/workflows/cpflow-deploy-review-app.yml@#{current_ref}"
      )
    end

    it "preserves an existing custom staging branch while updating generated wrappers" do
      inside_dir(playground) do
        run_cpflow_command!("generate-github-actions", "--force", "--staging-branch", "develop")
        result = run_cpflow_command("update-github-actions")

        expect(result[:status]).to eq(0)
      end

      expect(staging_workflow_path.read).to include('branches: ["develop"]')
      expect(staging_workflow_path.read).to include('staging_app_branch_default: "develop"')
    end

    it "treats a reversed default branch list as the default during update" do
      staging_workflow_path.write(
        staging_workflow_path.read.gsub('branches: ["main", "master"]', 'branches: ["master", "main"]')
      )

      inside_dir(playground) do
        result = run_cpflow_command("update-github-actions")

        expect(result[:status]).to eq(0)
        expect(result[:stderr]).not_to include("multiple custom push branches")
      end

      expect(staging_workflow_path.read).to include('branches: ["main", "master"]')
      expect(staging_workflow_path.read).to include('staging_app_branch_default: ""')
    end

    it "regenerates wrappers without crashing when the staging workflow is empty" do
      staging_workflow_path.write("")

      inside_dir(playground) do
        result = run_cpflow_command("update-github-actions")

        expect(result[:status]).to eq(0)
      end

      expect(staging_workflow_path.read).to include('branches: ["main", "master"]')
    end

    it "generates local helpers for pinning and validating cpflow workflow refs" do
      expect(pin_cpflow_ref_path.read).to include("Use a full 40-character commit SHA")
      expect(pin_cpflow_ref_path.read).to include("production")
      expect(pin_cpflow_ref_path.read).to include("control_plane_flow_ref:")
      expect(pin_cpflow_ref_path.read).to include("Pathname.new(path).relative_path_from(root).to_s")
      expect(test_cpflow_flow_path.read).to include("cpflow github-flow-readiness")
      expect(test_cpflow_flow_path.read).to include(
        "passes obsolete control_plane_flow_ref"
      )
      expect(test_cpflow_flow_path.read).to include("uses secrets: inherit")
      expect(test_cpflow_flow_path.read).to include("must not call the cross-repo production reusable workflow")
      expect(test_cpflow_flow_path.read).to include("must run as a normal caller-repo job")
      expect(test_cpflow_flow_path.read).to include("promote-to-production job is missing")
      expect(test_cpflow_flow_path.read).to include("must declare environment: production")
      expect(test_cpflow_flow_path.read).to include("EXPECTED_CPFLOW_CHECKOUT_ACTION")
      expect(test_cpflow_flow_path.read).to include("must check out")
      expect(test_cpflow_flow_path.read).to include("must pin the Checkout control-plane-flow actions step")
      expect(test_cpflow_flow_path.read).to include(
        "shakacode/control-plane-flow/.github/workflows/cpflow-promote-staging-to-production.yml@vX.Y.Z"
      )
      expect(test_cpflow_flow_path.read).to include("cpflow workflow wrappers use multiple upstream refs")
      expect(test_cpflow_flow_path.read).to include("workflow_(ref|sha|repository|file_path)")
    end

    it "passes setup action versions through env before using them in shell commands" do
      contents = setup_action_path.read

      expect(contents).to include("CONTROL_PLANE_FLOW_REF: ${{ inputs.control_plane_flow_ref }}")
      expect(contents).to include("CPLN_CLI_VERSION: ${{ inputs.cpln_cli_version }}")
      expect(contents).to include("CPFLOW_VERSION: ${{ inputs.cpflow_version }}")
      expect(contents).to include("normalize_version")
      expect(contents).to include("verify_release_ref_matches_checkout")
      expect(contents).to include("git ls-remote --tags")
      expect(contents).to include("timeout 20 git ls-remote")
      expect(contents).to include("is_rubygems_version")
      expect(contents).to include("extract_ref_name")
      expect(contents).to include("CPFLOW_VERSION must be a RubyGems version usable by 'gem install cpflow -v'")
      expect(contents).to include("validate_cpflow_version_pin")
      expect(contents).to include("CPFLOW_VERSION must match the control-plane-flow reusable workflow tag")
      expect(contents).to include("CPFLOW_VERSION can only be used when the control-plane-flow reusable workflow")
      expect(contents).to include("Use the real release tag ref, not a moving branch")
      expect(contents).to include("outbound HTTPS access to GitHub")
      expect(contents).not_to include("normalized CPFLOW_VERSION=${actual_version:-<unrecognized>}")
      expect(contents).to include("ruby/setup-ruby intentionally tracks the v1 tag")
      expect(contents).to include('default_ruby_version="3.2"')
      expect(contents).to include("minimum-supported Ruby advances")
      expect(contents).to include("ruby-version: ${{ steps.ruby-version.outputs.ruby_version }}")
      expect(contents).to include("${working_directory}/mise.toml")
      expect(contents).to include("${working_directory}/.mise.toml")
      expect(contents).to include('grep -Eq "^[[:space:]]*ruby[[:space:]]+" "${working_directory}/.tool-versions"')
      expect(contents).to include('npm_global_prefix="${HOME}/.npm-global"')
      expect(contents).to include('echo "${npm_global_prefix}/bin" >> "$GITHUB_PATH"')
      expect(contents).to include(
        'npm install --global --prefix "${npm_global_prefix}" "@controlplane/cli@${CPLN_CLI_VERSION}"'
      )
      expect(contents).not_to include("sudo npm install")
      expect(contents).to include('if [[ -n "${CPFLOW_VERSION}" ]]; then')
      expect(contents).to include('gem install cpflow -v "${CPFLOW_VERSION}" --no-document')
      expect(contents).to include("gem build cpflow.gemspec --output")
      expect(contents).to include('delim="CPLN_TOKEN_DELIM_$(openssl rand -hex 8)"')
      expect(contents).not_to include("__CPFLOW_CPLN_TOKEN__")
      expect(contents).not_to include(
        "npm install -g @controlplane/cli@${{ inputs.cpln_cli_version }}"
      )
      expect(contents).not_to include("gem install cpflow -v ${{ inputs.cpflow_version }}")
    end

    it "lets reusable workflows derive their own upstream checkout and gem/ref validation ref" do
      # This validates checked-in reusable workflows, not generated app wrappers.
      Dir.glob(Cpflow.root_path.join(".github/workflows/cpflow-*.yml").to_s).each do |path|
        workflow = YAML.load_file(path, aliases: true)
        workflow_on = workflow["on"] || workflow[true]

        expect(workflow_on).to have_key("workflow_call"), "#{path} must declare a workflow_call trigger"

        workflow_call = workflow_on.fetch("workflow_call") || {}
        workflow_inputs = workflow_call.fetch("inputs", {})

        expect(workflow_inputs).not_to(
          have_key("control_plane_flow_ref"),
          "#{path} must not require downstream wrappers to pass control_plane_flow_ref"
        )

        workflow_name = File.basename(path)
        requires_cpflow_source = !%w[cpflow-help-command.yml cpflow-review-app-help.yml].include?(workflow_name)
        saw_cpflow_checkout = false
        saw_setup_environment = false

        workflow.fetch("jobs").each_value do |job|
          # Job-level `uses:` entries call reusable workflows; they cannot call composite actions directly.
          Array(job["steps"]).each do |step|
            if step["uses"] == "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd" &&
               step.dig("with", "path") == ".cpflow"
              saw_cpflow_checkout = true
              expect(step.fetch("with")).to include(
                "repository" => "${{ job.workflow_repository }}",
                "ref" => "${{ job.workflow_sha }}"
              ), "#{path} cpflow checkout must use the called workflow source"
            end

            next unless step["uses"] == "./.cpflow/.github/actions/cpflow-setup-environment"

            saw_setup_environment = true
            expect(step.fetch("with")).to include(
              "control_plane_flow_ref" => "${{ job.workflow_ref }}"
            ), "#{path} setup action call must pass job.workflow_ref"
          end
        end

        if requires_cpflow_source
          expect(saw_cpflow_checkout).to be(true), "#{path} must checkout .cpflow from the called workflow source"
          expect(saw_setup_environment).to be(true), "#{path} must invoke cpflow-setup-environment"
        end
      end
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
      contents = reusable_review_app_workflow_path.read
      expect(contents).to include("docker_build_extra_args: ${{ vars.DOCKER_BUILD_EXTRA_ARGS }}")
      expect(contents).to include("docker_build_ssh_key: ${{ secrets.DOCKER_BUILD_SSH_KEY }}")
      expect(contents).to include(
        "docker_build_ssh_known_hosts: ${{ vars.DOCKER_BUILD_SSH_KNOWN_HOSTS }}"
      )
    end

    it "gates review-app deploys by author_association and skips fork PRs" do
      contents = reusable_review_app_workflow_path.read
      expect(contents).to include("github.event.comment.author_association")
      expect(contents).to include("Review app deploys are skipped for fork pull requests.")
      expect(contents).to include("Review app deploys from fork pull requests require a branch")
      expect(contents).to include('echo "allowed=false" >> "$GITHUB_OUTPUT"')
    end

    it "keeps trusted generated actions separate from PR-controlled app code" do
      contents = reusable_review_app_workflow_path.read

      expect(contents).to include("repository: ${{ job.workflow_repository }}")
      expect(contents).to include("ref: ${{ job.workflow_sha }}")
      expect(contents).to include("path: .cpflow")
      expect(contents).to include("path: app")
      expect(contents).to include("persist-credentials: false")
      expect(contents).to include("rm -rf app/.git")
      expect(contents).to include("working-directory: app")
      expect(contents).to include("working_directory: app")
    end

    it "runs review-app Ruby setup from the checked-out app directory" do
      contents = reusable_review_app_workflow_path.read

      expect(contents).to match(
        %r{
          uses:\ \./\.cpflow/\.github/actions/cpflow-setup-environment
          .*?
          working_directory:\ app
        }mx
      )
      expect(setup_action_path.read).to include(
        "working-directory: ${{ inputs.working_directory }}"
      )
      expect(setup_action_path.read).to include(
        'grep -Eq "^[[:space:]]*ruby[[:space:]]*(\(|file:|[\'\"])" "${working_directory}/Gemfile"'
      )
    end

    it "passes GitHub event metadata through shell env vars instead of inline expressions" do
      contents = reusable_review_app_workflow_path.read

      expect(contents).to include("EVENT_NAME: ${{ github.event_name }}")
      expect(contents).to include("GH_REPO: ${{ github.repository }}")
      expect(contents).not_to include('case "${{ github.event_name }}"')
      expect(contents).not_to include('[[ "${{ github.event_name }}"')
    end

    it "distinguishes review-app not-found from cpflow exists errors" do
      contents = reusable_review_app_workflow_path.read

      expect(contents).to include("exists_status")
      expect(contents).to include("            3)")
      expect(contents).to include('echo "exists=false" >> "$GITHUB_OUTPUT"')
      expect(contents).to include("cpflow exists returned unexpected exit code")
    end

    it "documents that review app deployments bypass required branch-protection contexts" do
      expect(reusable_review_app_workflow_path.read).to include(
        "required_contexts: [], // intentional: review apps deploy regardless of required status checks"
      )
    end

    it "handles missing PR comment ids gracefully in the review-app workflow" do
      expect(reusable_review_app_workflow_path.read).to include(
        "Skipping PR comment update because no comment id was created."
      )
    end

    it "configures delete-review-app concurrency and handles missing comment ids" do
      contents = reusable_delete_review_workflow_path.read
      expect(contents).to include("concurrency:")
      expect(contents).to include('pull_request_friendly: "true"')
      expect(contents).to include("Checkout repository")
      expect(contents).to include("path: app")
      expect(contents).to include("working_directory: app")
      expect(delete_review_workflow_path.read).to include("pull_request_target:")
      expect(delete_review_workflow_path.read).to include("pull_request_target is intentional")
      expect(delete_review_workflow_path.read).to include("mirrors the upstream job guard")
      expect(delete_review_workflow_path.read).to include("CPLN_TOKEN_STAGING: ${{ secrets.CPLN_TOKEN_STAGING }}")
      expect(delete_review_workflow_path.read).not_to include("secrets: inherit")
      expect(contents).to include(
        "Skipping delete status comment update because no comment id was created."
      )
    end

    it "gates delete-review-app downstream steps on cpflow-validate-config readiness" do
      contents = reusable_delete_review_workflow_path.read

      expect(contents).to include("id: config")
      expect(contents).to match(/steps\.config\.outputs\.ready == 'true'/)
      expect(contents).to include("Finalizer still runs after delete failures")
      expect(contents).to include("if: always() && steps.config.outputs.ready == 'true'")
    end

    it "routes github-script step outputs through env vars instead of inline expressions" do
      review_contents = reusable_review_app_workflow_path.read

      expect(review_contents).not_to include('Number("${{ steps.create-comment.outputs.comment-id }}")')
      expect(review_contents).not_to include('"${{ steps.init-deployment.outputs.result }}"')
      expect(review_contents).not_to include('"${{ steps.workload.outputs.workload_url }}"')
      expect(review_contents).not_to include('"${{ job.status }}"')
      expect(review_contents).to include("COMMENT_ID: ${{ steps.create-comment.outputs.comment-id }}")
      expect(review_contents).to include("DEPLOYMENT_ID: ${{ steps.init-deployment.outputs.result }}")
      expect(review_contents).to include("APP_URL: ${{ steps.workload.outputs.app_url }}")
      expect(review_contents).to include("JOB_STATUS: ${{ job.status }}")

      delete_contents = reusable_delete_review_workflow_path.read

      expect(delete_contents).not_to include('Number("${{ steps.create-comment.outputs.comment-id }}")')
      expect(delete_contents).not_to include('"${{ job.status }}"')
      expect(delete_contents).to include("COMMENT_ID: ${{ steps.create-comment.outputs.comment-id }}")
      expect(delete_contents).to include("JOB_STATUS: ${{ job.status }}")
    end

    it "uses shell env vars for stale review cleanup inputs" do
      contents = reusable_cleanup_stale_review_apps_workflow_path.read
      wrapper = cleanup_stale_review_apps_workflow_path.read
      action_contents = shared_action_path("cpflow-resolve-review-config").read

      expect(wrapper).to include("Cleanup targets the current inferred review-app prefix")
      expect(contents).to include("Resolve review app config")
      expect(contents).to include("uses: ./.cpflow/.github/actions/cpflow-resolve-review-config")
      expect(contents).to include("configured_review_app_prefix: ${{ vars.REVIEW_APP_PREFIX }}")
      expect(contents).to include("configured_cpln_org_staging: ${{ vars.CPLN_ORG_STAGING }}")
      expect(action_contents).to include("def safe_load_yaml_file(path)")
      expect(action_contents).to include("YAML.method(:safe_load).parameters")
      expect(action_contents).to include("YAML.safe_load(contents, [], [], true)")
      expect(action_contents).to include("omitted when pr_number is empty")
      expect(action_contents).to include('config = safe_load_yaml_file(".controlplane/controlplane.yml")')
      expect(action_contents).to include("unless config.is_a?(Hash)")
      expect(action_contents).to include('apps = config["apps"]')
      expect(action_contents).to include("unless apps.is_a?(Hash)")
      expect(action_contents).to include("validate_github_env_value!")
      expect(action_contents).to include("PR_NUMBER must be a positive integer")
      expect(action_contents).to include("Could not resolve review app config")
      expect(action_contents).to include("must contain only letters, numbers, and hyphens")
      expect(action_contents).to include('File.open(ENV.fetch("GITHUB_ENV"), "a")')
      expect(action_contents).to include('File.open(ENV.fetch("GITHUB_OUTPUT"), "a")')
      expect(contents).to include("Checkout caller repository")
      expect(contents).to include("path: app")
      expect(contents).to include("working_directory: app")
      expect(contents).to include('cpflow cleanup-stale-apps -a "${REVIEW_APP_PREFIX}"')
      expect(contents).to include("working-directory: app\n        env:\n          REVIEW_APP_PREFIX:")
      expect(contents).not_to include('cpflow cleanup-stale-apps -a "${{ vars.REVIEW_APP_PREFIX }}"')
      expect(contents).not_to include("variable:REVIEW_APP_PREFIX")
      expect(contents).not_to include("variable:CPLN_ORG_STAGING")
      expect(contents).to include("persist-credentials: false")
      expect(contents).to include("working_directory: .cpflow")
    end

    it "wires the help workflow author_association gate" do
      contents = help_workflow_path.read
      expect(contents).to include("github.event.comment.author_association")
      expect(contents).to include("contents: read")
      expect(contents).not_to include("control_plane_flow_ref:")
      expect(contents).not_to include("secrets: inherit")
      expect(reusable_help_workflow_path.read).to include('fs.readFileSync(".github/cpflow-help.md"')
      expect(reusable_pr_open_help_workflow_path.read).not_to include("vars.REVIEW_APP_PREFIX != ''")
    end

    it "pins the +review-app-* workflow trigger strings" do
      expect(review_app_workflow_path.read).to include(command_body_match_expression("+review-app-deploy"))
      expect(delete_review_workflow_path.read).to include(command_body_match_expression("+review-app-delete"))
      expect(help_workflow_path.read).to include(command_body_match_expression("+review-app-help"))
    end

    it "reacts immediately to trusted review-app comment commands" do
      review_contents = reusable_review_app_workflow_path.read
      delete_contents = reusable_delete_review_workflow_path.read
      help_contents = reusable_help_workflow_path.read

      expect(review_contents).to include("React to deploy command")
      expect(review_contents).to include("continue-on-error: true")
      expect(review_contents).to include("comment_id: context.payload.comment.id")
      expect(review_contents).to include('content: "rocket"')

      expect(delete_contents).to include("React to delete command")
      expect(delete_contents).to include("continue-on-error: true")
      expect(delete_contents).to include("comment_id: context.payload.comment.id")
      expect(delete_contents).to include('content: "eyes"')

      expect(help_contents).to include("React to help command")
      expect(help_contents).to include("continue-on-error: true")
      expect(help_contents).to include("comment_id: context.payload.comment.id")
      expect(help_contents).to include('content: "eyes"')
    end

    it "uses rich review-app deployment comment formatting" do
      contents = reusable_review_app_workflow_path.read

      expect(contents).to include("## 🚀 Starting deployment process...")
      expect(contents).to include("🏗️ Building Docker image for PR #${process.env.PR_NUMBER}")
      expect(contents).to include("📝 [View Build Logs]")
      expect(contents).to include("🎮 [Control Plane Console]")
      expect(contents).to include("## 🚀 Deploying to Control Plane...")
      expect(contents).to include("**Waiting for deployment to be ready...**")
      expect(contents).to include("## 🎉 Deploy Complete!")
      expect(contents).to include("### [Open Review App]")
      expect(contents).to include(
        "_Deployment successful for PR #${process.env.PR_NUMBER}, commit ${process.env.PR_SHA}_"
      )
      expect(contents).to include("📋 [View Completed Action Build and Deploy Logs]")
    end

    it "waits for review-app workload health before finalizing deployment success" do
      contents = reusable_review_app_workflow_path.read

      expect(contents).to include("- name: Wait for deployment health")
      expect(contents).to include("id: health-check")
      expect(contents).to include("uses: ./.cpflow/.github/actions/cpflow-wait-for-health")
      expect(contents).to include("workload_name: ${{ env.PRIMARY_WORKLOAD || 'rails' }}")
      expect(contents).to include("app_name: ${{ steps.review-config.outputs.app_name }}")
      expect(contents).to include("org: ${{ steps.review-config.outputs.cpln_org }}")
      expect(contents).not_to include("REVIEW_APP_HEALTH_CHECK_ACCEPTED_STATUSES:")
      expect(contents).to include("max_retries: ${{ vars.REVIEW_APP_HEALTH_CHECK_RETRIES || '24' }}")
      expect(contents).to include(
        "interval_seconds: ${{ vars.REVIEW_APP_HEALTH_CHECK_INTERVAL || '15' }}"
      )
      expect(contents).to include(
        "accepted_statuses: ${{ vars.REVIEW_APP_HEALTH_CHECK_ACCEPTED_STATUSES || '200 301 302' }}"
      )
      expect(contents).to include("curl_max_time: ${{ vars.REVIEW_APP_HEALTH_CHECK_CURL_MAX_TIME || '10' }}")
    end

    it "prefers the deployed app_domain for review-app links when available" do
      contents = reusable_review_app_workflow_path.read

      expect(contents).to include('workload_url="$(cpln workload get "${workload_name}"')
      expect(contents).to include('gvc_json="$(cpln gvc get "${APP_NAME}" --org "${CPLN_ORG}" -o json')
      expect(contents).to include("Could not read GVC app_domain; falling back to workload endpoint.")
      expect(contents).to include('select(.name == "app_domain")')
      expect(contents).to include('host_suffix = ".cpln.app"')
      expect(contents).to include('cpln_gvc_alias_token = "$" + "(CPLN_GVC_ALIAS)"')
      expect(contents).to include(".gsub(cpln_gvc_alias_token, cpln_gvc_alias)")
      expect(contents).to include('.gsub("{{APP_NAME}}", app_name)')
      expect(contents).to include('echo "app_url=${app_url}"')
      expect(contents).to include("APP_URL: ${{ steps.workload.outputs.app_url }}")
      expect(contents).not_to include("APP_URL: ${{ steps.workload.outputs.workload_url }}")
    end

    it "builds review-app app_domain URLs from workload endpoints" do
      expect(
        run_review_app_url_script(
          workload_name: "rails",
          workload_url: "https://rails-abc123.cpln.app",
          app_domain_template: "https://rails-$(CPLN_GVC_ALIAS).example.test",
          app_name: "hichee-review-1"
        )
      ).to eq("https://rails-abc123.example.test/")

      expect(
        run_review_app_url_script(
          workload_name: "rails",
          workload_url: "https://rails-abc123.org-prefix.cpln.app",
          app_domain_template: "https://preview.example.test/{{APP_NAME}}?alias=$(CPLN_GVC_ALIAS)",
          app_name: "hichee-review-1"
        )
      ).to eq("https://preview.example.test/hichee-review-1?alias=abc123")

      expect(
        run_review_app_url_script(
          workload_name: "rails",
          workload_url: "not a uri",
          app_domain_template: "https://rails-$(CPLN_GVC_ALIAS).example.test",
          app_name: "hichee-review-1"
        )
      ).to eq("not a uri")

      expect(
        run_review_app_url_script(
          workload_name: "rails",
          workload_url: "https://rails-.cpln.app",
          app_domain_template: "https://rails-$(CPLN_GVC_ALIAS).example.test",
          app_name: "hichee-review-1"
        )
      ).to eq("https://rails-.cpln.app")

      expect(
        run_review_app_url_script(
          workload_name: "rails",
          workload_url: "https://custom.example.test",
          app_domain_template: "https://rails-$(CPLN_GVC_ALIAS).example.test",
          app_name: "hichee-review-1"
        )
      ).to eq("https://custom.example.test")
    end

    it "supports an animated deploy status icon with a repository override" do
      contents = reusable_review_app_workflow_path.read

      expect(contents).to include("DEPLOYING_ICON_URL: ${{ vars.REVIEW_APP_DEPLOYING_ICON_URL }}")
      expect(contents).to include("DEFAULT_DEPLOYING_ICON_URL")
      expect(contents).to include("Pinned to the commit that introduced this SVG for immutability.")
      expect(contents).to include("replace this SHA, and regenerate user workflows")
      expect(contents).to include(
        "https://raw.githubusercontent.com/shakacode/control-plane-flow/7632313232b751aaa0bc55a122bf0615ff490345/docs/assets/cpflow-deploying.svg"
      )
      expect(contents).to include('parsedUrl.protocol === "https:"')
      expect(contents).to include("new URL(configuredDeployingIconUrl)")
      expect(contents).to include('configuredDeployingIconUrl.toLowerCase() === "none"')
      expect(contents).to include('"⏳"')
      expect(contents).to include('<img src="${deployingIconUrl}" alt="Deploying" width="20" height="20" />')
    end

    it "ships the default animated deployment icon asset" do
      asset_path = Pathname.new(__dir__).join("../../docs/assets/cpflow-deploying.svg").expand_path

      expect(asset_path).to exist
      expect(asset_path.read).to include("<animateTransform")
    end

    it "pins the +review-app-* commands in the PR-open message" do
      pr_open_help = reusable_pr_open_help_workflow_path.read

      expect(pr_open_help).to include('"# Review app commands"')
      expect(pr_open_help).to include('"- `+review-app-deploy`"')
      expect(pr_open_help).to include('"- `+review-app-delete`"')
      expect(pr_open_help).to include('"- `+review-app-help`"')
      expect(pr_open_help).to include('"For setup details, comment `+review-app-help`."')
      expect(pr_open_help).not_to include("`CPLN_TOKEN_STAGING` secret")
      expect(pr_open_help).not_to include('"---"')

      wrapper = pr_open_help_workflow_path.read
      expect(wrapper).to include("This is intentionally unconditional")
      expect(wrapper).to include("vars.REVIEW_APP_PREFIX != '' || vars.CPLN_ORG_STAGING != ''")
      expect(wrapper).not_to include("control_plane_flow_ref:")
      expect(wrapper).not_to include("secrets: inherit")
    end

    it "pins the +review-app-* commands in the long-form help markdown" do
      help_md = playground.join(".github/cpflow-help.md").read

      expect(help_md).to include("`+review-app-deploy`")
      expect(help_md).to include("`+review-app-delete`")
      expect(help_md).to include("`+review-app-help`")
      expect(help_md).to include("You asked for review app help.")
      expect(help_md).to include("These commands are generated by [cpflow]")
      expect(help_md).to include("<details>")
      expect(help_md).to include("<summary>GitHub Actions setup and advanced options</summary>")
      expect(help_md).to include("## GitHub Actions Secrets")
      expect(help_md).to include("## GitHub Actions Variables")
      expect(help_md).to include("Service-account token scoped to the staging Control Plane org on controlplane.com.")
      expect(help_md).to include("Control Plane org on controlplane.com for staging and review apps.")
      expect(help_md).to include("A single trailing newline from GitHub's comment editor is accepted.")
      expect(help_md).to include("vars.REVIEW_APP_PREFIX != '' || vars.CPLN_ORG_STAGING != ''")
      expect(help_md).to include("Before the first staging deploy")
      expect(help_md).to include("cpflow setup-app -a")
      expect(help_md).to include("app secret policy")
      expect(help_md).to include("For public repositories, use a staging/review token")
      expect(help_md).to include("production Control Plane resources")
      expect(help_md).to include("Generated review-app deploys skip fork PR")
      expect(help_md).to include("heads because Docker builds use repository secrets")
      expect(help_md).to include("Review apps run pull request code")
      expect(help_md).to include("review-app secret dictionaries limited to disposable databases")
      expect(help_md).to include("Add it as a secret on the 'production' GitHub Environment")
      expect(help_md).to include("permission to manage repository environments and secrets")
      expect(help_md).to include("gh secret set CPLN_TOKEN_PRODUCTION --repo OWNER/REPO --env production")
      expect(help_md).to include("gh secret list --repo OWNER/REPO --env production")
      expect(help_md).not_to include("control_plane_flow_ref")
    end

    it "documents Capacity AI guidance in the generated help markdown" do
      help_md = playground.join(".github/cpflow-help.md").read
      normalized_help = help_md.gsub(/\s+/, " ")
      # Exact phrasing -- update alongside the cpflow-help.md template if this copy changes.
      expected_guidance =
        "keep the app workload `type: standard` with one warm replica, " \
        "set its autoscaling metric to `disabled`, " \
        "and enable `capacityAI: true` so Control Plane can right-size CPU and memory allocation at that fixed " \
        "replica count"

      expect(normalized_help).to include(expected_guidance)
      expect(help_md).to include("Shared Postgres")
      expect(help_md).to include("stateful workloads")
      expect(help_md).to include("supported stateless app/service workloads")
      expect(help_md).to include("delete/recreate migration")
      expect(help_md).not_to include("serverless web workload with `minScale: 0`")
    end

    it "documents Docker build vars in the help markdown" do
      help_md_path = playground.join(".github/cpflow-help.md")
      contents = help_md_path.read
      expect(contents).to include("DOCKER_BUILD_EXTRA_ARGS")
      expect(contents).to include("Read-only, revocable deploy key")
      expect(contents).to include("Do not use a personal SSH key")
      expect(contents).to include("DOCKER_BUILD_SSH_KNOWN_HOSTS")
    end

    # Issue #341: the version-locking example must not emit a concrete release number.
    # A literal version (e.g. 5.0.1) goes stale against the @v#{VERSION} wrapper refs in
    # the same generated file and reads like a required old runtime override.
    it "uses a placeholder version in the CPFLOW_VERSION example" do
      help_md = playground.join(".github/cpflow-help.md").read

      expect(help_md).to match(/CPFLOW_VERSION=\d+\.\d+\.x\b/)
      expect(help_md).to match(/uses: \.\.\.@v\d+\.\d+\.x\b/)
      expect(help_md).not_to match(/CPFLOW_VERSION=\d+\.\d+\.\d+/)
    end

    it "documents the review-app deploying icon override in the help markdown" do
      help_md = playground.join(".github/cpflow-help.md").read

      expect(help_md).to include("REVIEW_APP_DEPLOYING_ICON_URL")
      expect(help_md).to include("Set to `none` to use the text fallback icon.")
    end

    it "wires Docker build inputs through the staging workflow" do
      contents = reusable_staging_workflow_path.read
      expect(contents).to include("docker_build_extra_args: ${{ vars.DOCKER_BUILD_EXTRA_ARGS }}")
      expect(contents).to include("docker_build_ssh_key: ${{ secrets.DOCKER_BUILD_SSH_KEY }}")
      expect(contents).to include(
        "docker_build_ssh_known_hosts: ${{ vars.DOCKER_BUILD_SSH_KNOWN_HOSTS }}"
      )
      expect(contents.scan("working_directory: .cpflow").length).to eq(2)
    end

    it "does not persist checkout credentials in staging jobs" do
      expect(reusable_staging_workflow_path.read.scan("persist-credentials: false").length).to eq(5)
    end

    it "documents the branch-filter trade-off and sets staging concurrency/vars" do
      wrapper = staging_workflow_path.read
      reusable = reusable_staging_workflow_path.read

      expect(wrapper).to include("GitHub does not allow repository vars in branch filters")
      expect(wrapper).to include('branches: ["main", "master"]')
      expect(wrapper).to include('staging_app_branch_default: ""')
      expect(reusable).to include(
        "STAGING_APP_BRANCH: ${{ vars.STAGING_APP_BRANCH || inputs.staging_app_branch_default }}"
      )
      expect(reusable).to include("cpflow-deploy-staging-${{ github.ref_name }}")
      expect(reusable).to include("variable:STAGING_APP_NAME")
    end

    it "configures the promote workflow's concurrency, release tagging, and rollback guard" do
      contents = reusable_promote_workflow_path.read
      wrapper = promote_workflow_path.read
      default_ref = "v#{Cpflow::VERSION}"
      production_workflow_ref = "shakacode/control-plane-flow/.github/workflows/" \
                                "cpflow-promote-staging-to-production.yml"

      expect(wrapper).to include("This normal caller-repo job declares the protected production Environment")
      expect(wrapper).to include("environment: production")
      expect(wrapper).to include("HEALTH_CHECK_RETRIES: ${{ vars.HEALTH_CHECK_RETRIES || '24' }}")
      expect(wrapper).to include("COPY_IMAGE_RETRIES: ${{ vars.COPY_IMAGE_RETRIES || '3' }}")
      expect(wrapper).to include("COPY_IMAGE_RETRY_INTERVAL: ${{ vars.COPY_IMAGE_RETRY_INTERVAL || '20' }}")
      expect(wrapper).to include("ROLLBACK_READINESS_RETRIES: ${{ vars.ROLLBACK_READINESS_RETRIES || '24' }}")
      expect(wrapper).to include("repository: shakacode/control-plane-flow")
      expect(wrapper).to include("ref: #{default_ref}")
      expect(wrapper).to include("control_plane_flow_ref: #{production_workflow_ref}@#{default_ref}")
      expect(wrapper).to include("CPLN_TOKEN_STAGING: ${{ secrets.CPLN_TOKEN_STAGING }}")
      expect(wrapper).to include("CPLN_TOKEN_PRODUCTION: ${{ secrets.CPLN_TOKEN_PRODUCTION }}")
      expect(wrapper).not_to include("uses: #{production_workflow_ref}")
      expect(wrapper).not_to include("production_environment: production")
      expect(wrapper).not_to include("secrets: inherit")
      expect(contents).to include("group: cpflow-promote-staging-to-production")
      expect(contents).to include("contents: read")
      expect(contents).to include("production_environment:")
      expect(contents).to include("default: production")
      expect(contents).to include("environment: ${{ inputs.production_environment }}")
      expect(contents).to include("Validate production token")
      expect(contents).to include("CPLN_TOKEN_PRODUCTION is not set")
      expect(contents).to include("Normalize Control Plane org names")
      expect(contents).to include("contains embedded line endings")
      expect(contents).to include("steps.cpln-orgs.outputs.production")
      expect(wrapper).to include("Normalize Control Plane org names")
      expect(wrapper).to include("contains embedded line endings")
      expect(wrapper).to include("steps.cpln-orgs.outputs.production")
      expect(contents).to include("wrapper intentionally passes only CPLN_TOKEN_STAGING")
      expect(contents).to include("create-github-release:")
      expect(contents).to include("contents: write")
      expect(contents).to include("working_directory: .cpflow")
      expect(contents).to include("GH_REPO: ${{ github.repository }}")
      expect(contents).to include("Production-only variables")
      expect(contents).to include("WORKLOAD_NAMES: ${{ steps.workloads.outputs.names }}")
      expect(contents).to include("list_workload_env_names()")
      expect(contents).to include("check_required_vars intentionally mutates env_check_failed")
      expect(contents).to include(
        "Production workload '${workload_name}' is missing environment variables that exist in staging"
      )
      expect(wrapper).to include("WORKLOAD_NAMES: ${{ steps.workloads.outputs.names }}")
      expect(wrapper).to include("list_workload_env_names()")
      expect(wrapper).to include("check_required_vars intentionally mutates env_check_failed")
      expect(wrapper).to include(
        "Production workload '${workload_name}' is missing environment variables that exist in staging"
      )
      expect(contents).to include("PRIMARY_WORKLOAD is not configured")
      expect(contents).to include(%(puts "primary=\#{primary}"))
      expect(contents).to include("PRIMARY_WORKLOAD: ${{ steps.workloads.outputs.primary }}")
      expect(contents).to include("map({name, image})")
      expect(contents).to include("Could not retrieve current containers")
      expect(contents).to include("Could not parse rollback state")
      expect(contents).to include("Could not parse captured containers")
      expect(contents).to include("Could not build rollback image list")
      expect(contents).to include(".status.readyLatest // false")
      expect(wrapper).to include(".status.readyLatest // false")
      expect(contents).to include("Container set changed")
      expect(contents).to include('jq -r \'.[] | "\\(.name)\\t\\(.image)"\'')
      expect(contents).to include("spec.containers.${container_name}.image")
      expect(contents).not_to include("spec.containers[${index}].image")
      expect(contents).not_to include("index($container.name)")
      expect(contents).to include(
        'release_tag="production-${release_date}-${timestamp}-${GITHUB_RUN_ID}"'
      )
      expect(contents).to include("workflow-level concurrency group keeps production promotion copy")
      expect(contents).to include(
        "failure() && steps.capture-current.outputs.rollback_state != '' && " \
        "steps.capture-current.outputs.rollback_state != '{}'"
      )
    end

    it "does not persist checkout credentials in the production promotion job" do
      expect(reusable_promote_workflow_path.read.scan("persist-credentials: false").length).to eq(2)
    end

    it "copies the image currently deployed on staging instead of the newest pushed staging image" do
      contents = reusable_promote_workflow_path.read
      wrapper = promote_workflow_path.read

      expect(contents).to include("id: staging-image")
      expect(contents).to include('CPLN_TOKEN="${CPLN_TOKEN_STAGING}" cpln workload get')
      expect(contents).to include('selected_workload="${PRIMARY_WORKLOAD}"')
      expect(contents).not_to include('selected_workload="${PRIMARY_WORKLOAD:-}"')
      expect(contents).to include("staging_image=\"${staging_image_ref##*/image/}\"")
      expect(contents).to include("STAGING_IMAGE: ${{ steps.staging-image.outputs.image }}")
      expect(contents).to include(
        'staging_org="$(sanitize_control_plane_name "CPLN_ORG_STAGING" ' \
        '"${CPLN_ORG_STAGING}")"'
      )
      expect(contents).to include(
        'production_org="$(sanitize_control_plane_name "CPLN_ORG_PRODUCTION" ' \
        '"${CPLN_ORG_PRODUCTION}")"'
      )
      expect(contents).to include("use lowercase alphanumeric characters and hyphens only")
      expect(contents).to include("CPLN_ORG_STAGING: ${{ steps.cpln-orgs.outputs.staging }}")
      expect(contents).to include("CPLN_ORG_PRODUCTION: ${{ steps.cpln-orgs.outputs.production }}")
      expect(contents).to include("COPY_IMAGE_RETRIES must be a non-negative integer")
      expect(contents).to include("COPY_IMAGE_RETRY_INTERVAL must be a non-negative integer")
      expect(contents).to include("copy_image_attempts=$((copy_image_retries + 1))")
      expect(contents).to include("Staging image '${STAGING_IMAGE}' was not found")
      expect(contents).to include(
        "uses: docker/setup-buildx-action@d7f5e7f509e45cec5c76c4d5afdd7de93d0b3df5"
      )
      expect(contents).to include("id: copy-image")
      expect(contents).to include('staging_image="${STAGING_IMAGE}"')
      expect(contents).to include("STAGING_IMAGE is not set or is empty")
      expect(contents).not_to include('staging_image="${STAGING_IMAGE%%@*}"')
      expect(contents).to include('CPLN_TOKEN="${CPLN_TOKEN_STAGING}" cpln image get "${staging_image}"')
      expect(contents).to include('if [[ "${staging_image}" == *@* ]]; then')
      expect(contents).to include('staging_tag="${staging_image##*@}"')
      expect(contents).to include('elif [[ "${staging_image}" == *:* ]]; then')
      expect(contents).to include('staging_tag="${staging_image##*:}"')
      expect(contents).to include('staging_commit=""')
      expect(contents).to include('if [[ "${staging_tag}" == *_* ]]; then')
      expect(contents).to include('staging_commit="${staging_tag##*_}"')
      expect(contents).to include("workflow-level concurrency group serializes this sequence")
      expect(contents).to include("top-level concurrency group: cpflow-promote-staging-to-production")
      expect(contents).to include("Staging image '${staging_image}' did not include a '_<commit>' suffix")
      expect(wrapper).to include("Staging image '${staging_image}' did not include a '_<commit>' suffix")
      expect(wrapper).to include("top-level concurrency group: cpflow-promote-staging-to-production")
      expect(contents).to include('--prop "name~${PRODUCTION_APP_NAME}:" --max 0')
      expect(contents).to include("Could not determine the next production image number")
      expect(contents).to include('production_image="${PRODUCTION_APP_NAME}:$((latest_number + 1))"')
      expect(contents).to include('production_image="${production_image}_${staging_commit}"')
      expect(contents).to include('docker_config_dir="$(mktemp -d)"')
      expect(contents).to include("cleanup_copy_credentials")
      expect(contents).to include('export DOCKER_CONFIG="${docker_config_dir}"')
      expect(contents).to include('staging_registry="${CPLN_ORG_STAGING}.registry.cpln.io"')
      expect(contents).to include('production_registry="${CPLN_ORG_PRODUCTION}.registry.cpln.io"')
      expect(contents).to include('source_image_ref="${staging_registry}/${STAGING_IMAGE}"')
      expect(contents).to include('production_image_ref="${production_registry}/${production_image}"')
      expect(contents).to include("CPLN_TOKEN_PRODUCTION: ${{ secrets.CPLN_TOKEN_PRODUCTION }}")
      expect(contents).to include('docker login "${staging_registry}"')
      expect(contents).to include('docker login "${production_registry}"')
      expect(contents).to include("Failed to authenticate to staging registry")
      expect(contents).to include("Failed to authenticate to production registry")
      expect(contents).to include('docker buildx imagetools inspect "${production_image_ref}"')
      expect(contents).to include('for attempt in $(seq 1 "${copy_image_attempts}"); do')
      expect(contents).to include('docker buildx imagetools inspect "${source_image_ref}"')
      expect(contents).to include(
        "docker buildx imagetools create --prefer-index=false --tag " \
        "\"${production_image_ref}\" \"${source_image_ref}\""
      )
      expect(contents).to include('echo "image=${production_image}" >> "$GITHUB_OUTPUT"')
      expect(contents).to include("COPIED_IMAGE: ${{ steps.copy-image.outputs.image }}")
      expect(contents).to include('deployed_image="${COPIED_IMAGE}"')
      expect(contents).to include('deployed_image="${PREVIOUS_IMAGE}"')
      expect(contents).to include("Image copy attempt ${attempt}/${copy_image_attempts} failed")
      expect(contents).to include("no attempts remain")
      expect(contents).to include("workload_name: ${{ steps.workloads.outputs.primary }}")
      expect(contents).not_to include("workload_name: ${{ env.PRIMARY_WORKLOAD || 'rails' }}")
      expect(contents).not_to include("CPLN_UPSTREAM_TOKEN:")
      expect(contents).not_to include("Pass the upstream token")
      expect(contents).not_to include('cpln profile create "${upstream_profile}"')
      expect(contents).not_to include("--profile \"${upstream_profile}\"")
      expect(contents).not_to include("cpln image docker-login")
      expect(contents).not_to include('cpln image copy "${STAGING_IMAGE}"')
      expect(contents).not_to include('docker manifest inspect "${source_image_ref}"')
      expect(contents).not_to include('docker pull "${source_image_ref}"')
      expect(contents).not_to include('docker tag "${source_image_ref}" "${production_image_ref}"')
      expect(contents).not_to include('docker push "${production_image_ref}"')
      expect(contents).not_to include("cpflow copy-image-from-upstream")
      expect(contents).not_to include("--cleanup")
    end

    it "detects release phase support from controlplane.yml instead of cpflow config text" do
      contents = detect_release_action_path.read

      expect(contents).to include('YAML.safe_load(File.read(".controlplane/controlplane.yml"), aliases: true)')
      expect(contents).to include("app_name.start_with?(name)")
      expect(contents).not_to include("cpflow config")
      expect(contents).not_to include("grep -qE")
    end

    it "emits a friendly error before reading a missing controlplane.yml" do
      contents = detect_release_action_path.read

      expect(contents).to include('unless File.file?(".controlplane/controlplane.yml")')
      expect(contents).to match(%r{`\.controlplane/controlplane\.yml` is missing.*?exit 1}m)
    end

    it "makes pull_request_target config validation skip cleanly when setup is incomplete" do
      contents = shared_action_path("cpflow-validate-config").read

      expect(contents).to include('pull_request_target"')
      expect(contents).to include('echo "ready=false" >> "$GITHUB_OUTPUT"')
    end

    it "reports a missing primary workload before polling health" do
      contents = wait_for_health_action_path.read

      expect(contents).to include("Workload '${CPFLOW_WORKLOAD_NAME}' not found")
      expect(contents).to include("Set PRIMARY_WORKLOAD to the correct workload name.")
      expect(contents).to include("has no endpoint yet; waiting for one to be assigned")
      expect(contents).to include(".status.readyLatest // false")
      expect(contents).to include("readyLatest=${latest_ready}")
    end

    it "writes the delete-app script with the not-found guard message" do
      contents = delete_app_script_path.read

      expect(contents).to include("⚠️ Application does not exist")
      expect(contents).to include("exists_status")
      expect(contents).to include("  3)")
      expect(contents).to include("failed to determine whether application exists")
    end

    it "produces valid YAML for every generated workflow and action file" do
      (generated_yaml_paths + shared_yaml_paths).each do |path|
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
        # Re-derive __CPFLOW_MINOR_SERIES__ here rather than calling cpflow_minor_series,
        # so this snapshot guard stays independent of the code under test.
        expected = template
                   .gsub("__CPFLOW_GITHUB_ACTIONS_REF__", "v#{Cpflow::VERSION}")
                   .gsub("__CPFLOW_MINOR_SERIES__", "#{Cpflow::VERSION.split('.').first(2).join('.')}.x")
                   .gsub("__STAGING_BRANCH_FILTER__", %("main", "master"))
                   .gsub("__STAGING_BRANCH_DEFAULT__", "")
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

      generated = Dir.glob(playground.join("**", "*").to_s, File::FNM_DOTMATCH)
                     .select { |path| File.file?(path) }
                     .map { |path| Pathname.new(path).relative_path_from(playground).to_s }
                     .sort

      expect(generated).to eq(expected)
    end
  end

  context "when update-github-actions runs in a fresh repository" do
    it "aborts with a clear message instead of silently bootstrapping wrappers" do
      inside_dir(playground) do
        result = run_cpflow_command("update-github-actions")

        expect(result[:status]).to eq(ExitCode::ERROR_DEFAULT)
        expect(result[:stderr]).to include("No generated cpflow GitHub Actions files")
        expect(result[:stderr]).to include("cpflow generate-github-actions")
        expect(playground.join(".github")).not_to exist
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
        expect(staging_workflow_path).not_to exist
      end
    end
  end

  context "when CPFLOW_GITHUB_ACTIONS_REF is blank" do
    before do
      stub_env("CPFLOW_GITHUB_ACTIONS_REF", "  ")
      inside_dir(playground) do
        Cpflow::Cli.start([described_class::NAME])
      end
    end

    it "falls back to the release tag default" do
      default_ref = "v#{Cpflow::VERSION}"

      expect(review_app_workflow_path.read).to include(
        "shakacode/control-plane-flow/.github/workflows/cpflow-deploy-review-app.yml@#{default_ref}"
      )
      expect(review_app_workflow_path.read).not_to include("control_plane_flow_ref:")
    end
  end

  context "when CPFLOW_GITHUB_ACTIONS_REF contains whitespace" do
    it "aborts before generating invalid workflow refs" do
      stub_env("CPFLOW_GITHUB_ACTIONS_REF", "feature branch")

      inside_dir(playground) do
        result = run_cpflow_command(described_class::NAME)

        expect(result[:status]).to eq(ExitCode::ERROR_DEFAULT)
        expect(result[:stderr]).to include("Invalid CPFLOW_GITHUB_ACTIONS_REF")
        expect(playground.join(".github")).not_to exist
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
      expect(contents).to include('staging_app_branch_default: "release@2025"')
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
