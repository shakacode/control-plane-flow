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

    it "scopes the Control Plane org queue per PR (or ref) and never cancels queued runs" do
      # The group keys on PR number (or ref for non-PR events), so a PR's own runs
      # serialize against each other but unrelated PRs don't share one blocking
      # queue. cancel-in-progress is false, so queued runs wait rather than cancel.
      expected_group =
        "cpln-shared-org-${{ vars.CPLN_ORG || github.run_id }}-" \
        "${{ github.event.pull_request.number || github.ref }}"

      expect(job.fetch("concurrency")).to eq(
        "group" => expected_group,
        "cancel-in-progress" => false
      )
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
