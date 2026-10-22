# frozen_string_literal: true

require "spec_helper"
require "yaml"
require "open3"

RSpec.describe "Review app deploy lock" do # rubocop:disable RSpec/DescribeClass
  it "acquires and releases within the deploy job on every attempt" do
    workflow = YAML.safe_load_file(File.expand_path("../.github/workflows/cpflow-deploy-review-app.yml", __dir__))
    steps = workflow.fetch("jobs").fetch("deploy").fetch("steps")
    acquire = steps.find { |step| step["name"] == "Acquire shared deployment lock" }
    release = steps.find { |step| step["name"] == "Release shared deployment lock" }

    expect(acquire).not_to be_nil
    expect(release).not_to be_nil
    expect(steps.index(acquire)).to be < steps.index { |step| step["name"] == "Check if review app exists" }
    expect(release.fetch("if")).to include("always()", "!cancelled()", "steps.deploy-lock.outcome == 'success'")
    expect(acquire.fetch("if")).to include("inputs.deployment_lock")
    expect(acquire.fetch("env").fetch("DEPLOY_OWNER")).to include("github.run_id", "github.run_attempt")
    expect(workflow.fetch("on", workflow[true]).fetch("workflow_call").fetch("inputs").fetch("deployment_lock")).to(
      include("type" => "boolean", "default" => false)
    )
  end

  it "enforces ownership and failure handling without contacting Control Plane" do
    stdout, stderr, status = Open3.capture3(
      { "PYTHONDONTWRITEBYTECODE" => "1" }, "python3", File.expand_path("deployment_lock_test.py", __dir__)
    )

    expect(status.success?).to be(true), "#{stdout}\n#{stderr}"
  end
end
