# frozen_string_literal: true

require "spec_helper"
require "yaml"

RSpec.describe "GitHub workflow definitions" do # rubocop:disable RSpec/DescribeClass
  describe "Review app comment authorization" do
    def workflow_file(name)
      YAML.safe_load_file(File.expand_path("../.github/workflows/#{name}", __dir__), aliases: true)
    end

    {
      "cpflow-deploy-review-app.yml" => "deploy",
      "cpflow-delete-review-app.yml" => "delete-review-app"
    }.each do |workflow_name, command_job_name|
      it "requires write permission before running #{command_job_name} comment commands" do
        workflow = workflow_file(workflow_name)
        authorization_job = workflow.fetch("jobs").fetch("authorize-comment-command")
        permission_step = authorization_job.fetch("steps").find do |step|
          step["name"] == "Resolve comment author repository permission"
        end
        non_comment_step = authorization_job.fetch("steps").find do |step|
          step["name"] == "Allow authenticated non-comment trigger"
        end
        script = permission_step.fetch("run")
        command_job = workflow.fetch("jobs").fetch(command_job_name)

        expect(authorization_job.fetch("permissions")).to eq("contents" => "read")
        expect(authorization_job.fetch("outputs")).to eq(
          "allowed" => "${{ steps.permission.outputs.allowed || steps.non-comment.outputs.allowed }}"
        )
        expect(permission_step).not_to have_key("uses")
        expect(permission_step).to include(
          "shell" => "bash",
          "env" => {
            "GH_TOKEN" => "${{ github.token }}",
            "GH_REPO" => "${{ github.repository }}",
            "COMMENT_AUTHOR" => "${{ github.event.comment.user.login }}"
          }
        )
        expect(script).to include("set -euo pipefail")
        expect(script).to include(%(printf '%s\\n' 'allowed=false' >> "$GITHUB_OUTPUT"))
        expect(script).to include(
          %(gh api --method GET "repos/${GH_REPO}/collaborators/${COMMENT_AUTHOR}/permission" --jq '.permission')
        )
        expect(script).to include("write|maintain|admin)")
        expect(script).to include("read|triage|none)")
        expect(script).to include(%(printf '%s\\n' 'allowed=true' >> "$GITHUB_OUTPUT"))
        expect(script).to include('if [[ -z "${permission}" ]]')
        expect(script).to include("Unexpected repository permission")
        expect(script).not_to include("${{")
        expect(non_comment_step).to include(
          "if" => "github.event_name != 'issue_comment'",
          "run" => include("allowed=true")
        )
        expect(command_job.fetch("needs")).to eq("authorize-comment-command")
        expect(command_job.fetch("if")).to include(
          "needs.authorize-comment-command.outputs.allowed == 'true'"
        )
        expect(command_job.fetch("if")).not_to include("github.event.comment.author_association")
        expect(workflow).not_to have_key("concurrency")
        expect(command_job.fetch("concurrency")).to include(
          "group" => start_with("cpflow-review-app-"),
          "cancel-in-progress" => false
        )
      end
    end
  end

  describe "RSpec shared workflow" do
    let(:workflow) do
      YAML.safe_load_file(
        File.expand_path("../.github/workflows/rspec-shared.yml", __dir__),
        aliases: true
      )
    end

    let(:job) { workflow.fetch("jobs").fetch("rspec") }

    it "serializes shared-org runs while keeping fast queues per PR (or ref)" do
      # Scheduled, slow, and specific runs that can touch the live domain share
      # one queue. Fast runs remain scoped by PR number (or ref) so unrelated
      # PRs don't share one blocking queue. Queued runs never cancel each other.
      expected_group =
        "cpln-shared-org-${{ vars.CPLN_ORG || github.repository }}-" \
        "${{ inputs.uses_shared_org && 'shared-org' || github.event.pull_request.number || github.ref }}"

      expect(job.fetch("concurrency")).to eq(
        "group" => expected_group,
        "cancel-in-progress" => false
      )
    end
  end

  describe "RSpec workflow callers" do
    def workflow_file(name)
      YAML.safe_load_file(File.expand_path("../.github/workflows/#{name}", __dir__), aliases: true)
    end

    it "marks slow and specific runs as shared-org consumers" do
      rspec_jobs = workflow_file("rspec.yml").fetch("jobs")
      specific_jobs = workflow_file("rspec-specific.yml").fetch("jobs")

      expect(rspec_jobs.fetch("rspec-slow").fetch("with")).to include("uses_shared_org" => true)
      expect(specific_jobs.fetch("rspec-specific").fetch("with")).to include("uses_shared_org" => true)
      expect(rspec_jobs.fetch("rspec-fast").fetch("with")).not_to have_key("uses_shared_org")
    end
  end

  describe "Delete Review App workflow" do
    let(:workflow) do
      YAML.safe_load_file(
        File.expand_path("../.github/workflows/cpflow-delete-review-app.yml", __dir__),
        aliases: true
      )
    end

    let(:steps) { workflow.fetch("jobs").fetch("delete-review-app").fetch("steps") }

    let(:deploy_workflow) do
      YAML.safe_load_file(
        File.expand_path("../.github/workflows/cpflow-deploy-review-app.yml", __dir__),
        aliases: true
      )
    end

    def step_named(name)
      steps.find { |step| step["name"] == name }
    end

    it "runs cpflow delete from a downstream app checkout" do
      expect(step_named("Checkout repository")).to include(
        "uses" => "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd",
        "with" => include(
          "path" => "app",
          "persist-credentials" => false
        )
      )

      expect(step_named("Setup environment").fetch("with")).to include(
        "working_directory" => "app"
      )
      expect(step_named("Delete review app").fetch("with")).to include(
        "working_directory" => "app"
      )
    end

    it "deactivates every GitHub deployment for the deleted review environment" do
      expect(workflow.fetch("permissions")).to include("deployments" => "write")

      step = step_named("Deactivate GitHub review deployments")
      expect(step).to include(
        "id" => "deactivate-deployments",
        "continue-on-error" => true,
        "if" => "steps.config.outputs.ready == 'true' && steps.delete-app.outcome == 'success'",
        "env" => {
          "APP_NAME" => "${{ steps.review-config.outputs.app_name }}"
        }
      )

      script = step.fetch("with").fetch("script")
      expect(script).to include("const environment = `review/${process.env.APP_NAME}`;")
      expect(script).to include("github.paginate(github.rest.repos.listDeployments")
      expect(script).to include("github.rest.repos.listDeploymentStatuses")
      expect(script).to include('latestStatus?.state === "inactive"')
      expect(script).to include("for (const deployment of deployments)")
      expect(script).to include("github.rest.repos.createDeploymentStatus")
      expect(script).to include('state: "inactive"')
    end

    it "reports deployment cleanup failures accurately before failing the workflow" do
      expect(step_named("Delete review app")).to include("id" => "delete-app")

      finalizer = step_named("Finalize delete status")
      expect(finalizer.fetch("env")).to include(
        "DELETE_OUTCOME" => "${{ steps.delete-app.outcome }}",
        "DEACTIVATION_OUTCOME" => "${{ steps.deactivate-deployments.outcome }}"
      )
      expect(finalizer.dig("with", "script")).to include(
        "Review App Deleted, GitHub Deployment Cleanup Failed"
      )

      failure_step = step_named("Fail when GitHub deployment cleanup failed")
      expect(failure_step.fetch("if")).to include("steps.deactivate-deployments.outcome == 'failure'")
      expect(failure_step.fetch("run")).to include("exit 1")
      expect(steps.index(finalizer)).to be < steps.index(failure_step)
    end

    it "serializes deploy and delete workflows in the same per-PR concurrency group" do
      delete_concurrency = workflow.dig("jobs", "delete-review-app", "concurrency")
      deploy_concurrency = deploy_workflow.dig("jobs", "deploy", "concurrency")

      expect(delete_concurrency).to eq(deploy_concurrency)
      expect(delete_concurrency.fetch("group")).to start_with("cpflow-review-app-")
      expect(delete_concurrency.fetch("cancel-in-progress")).to be(false)
    end

    it "creates future review deployments as transient environments" do
      deploy_steps = deploy_workflow.fetch("jobs").fetch("deploy").fetch("steps")
      init_step = deploy_steps.find { |step| step["name"] == "Initialize GitHub deployment" }
      script = init_step.fetch("with").fetch("script")

      expect(script).to include("transient_environment: true")
      expect(script).to include("production_environment: false")
    end

    it "rejects fork sources before checking out or building pull request code" do
      deploy_steps = deploy_workflow.fetch("jobs").fetch("deploy").fetch("steps")
      source_index = deploy_steps.index { |step| step["name"] == "Validate review app deployment source" }
      checkout_index = deploy_steps.index { |step| step["name"] == "Checkout PR commit" }
      build_index = deploy_steps.index { |step| step["name"] == "Build Docker image" }

      expect(source_index).to be < checkout_index
      expect(source_index).to be < build_index
    end
  end

  describe "Delete Control Plane App action" do
    let(:action) do
      YAML.safe_load_file(
        File.expand_path("../.github/actions/cpflow-delete-control-plane-app/action.yml", __dir__),
        aliases: true
      )
    end

    it "allows callers to choose the project working directory" do
      expect(action.fetch("inputs")).to include(
        "working_directory" => include("default" => ".")
      )

      delete_step = action.fetch("runs").fetch("steps").find { |step| step["name"] == "Delete application" }

      expect(delete_step).to include(
        "working-directory" => "${{ inputs.working_directory }}"
      )
    end
  end
end
