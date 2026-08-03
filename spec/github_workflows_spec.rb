# frozen_string_literal: true

require "spec_helper"
require "yaml"

RSpec.describe "GitHub workflow definitions" do # rubocop:disable RSpec/DescribeClass
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
      expect(workflow.fetch("concurrency")).to eq(deploy_workflow.fetch("concurrency"))
      expect(workflow.dig("concurrency", "group")).to start_with("cpflow-review-app-")
      expect(workflow.dig("concurrency", "cancel-in-progress")).to be(false)
    end

    it "creates future review deployments as transient environments" do
      deploy_steps = deploy_workflow.fetch("jobs").fetch("deploy").fetch("steps")
      init_step = deploy_steps.find { |step| step["name"] == "Initialize GitHub deployment" }
      script = init_step.fetch("with").fetch("script")

      expect(script).to include("transient_environment: true")
      expect(script).to include("production_environment: false")
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
