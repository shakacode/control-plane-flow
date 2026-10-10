# frozen_string_literal: true

require "spec_helper"

RSpec.describe "CI automation documentation" do # rubocop:disable RSpec/DescribeClass
  let(:documentation) { File.read(File.expand_path("../docs/ci-automation.md", __dir__)) }
  let(:contributing) { File.read(File.expand_path("../CONTRIBUTING.md", __dir__)) }
  let(:normalized_documentation) { documentation.gsub(/\s+/, " ") }
  let(:normalized_contributing) { contributing.gsub(/\s+/, " ") }

  it "gives executable paths for testing unmerged downstream generated files" do
    expect(normalized_documentation).to include(
      "gh workflow run cpflow-deploy-review-app.yml --ref <downstream-test-branch> " \
      "-f pr_number=<pr-number>"
    )
    expect(normalized_documentation).to include(
      "`issue_comment` always loads the workflow definition from the default branch"
    )
    expect(normalized_documentation).to include("cannot validate unmerged wrappers.")
    expect(normalized_documentation).to include("For a first installation")
    expect(normalized_documentation).to include("run the local contract before merging")
    expect(normalized_documentation).to include("dispatch the merged workflow immediately afterward")
  end

  it "documents the exact-release-tag exception for generated reusable-workflow calls" do
    expect(normalized_documentation).to include(
      "intentional downstream exception to the repository's full-SHA external-action policy"
    )
    expect(normalized_documentation).to include("exact release tag such as `v5.0.0`")
  end

  it "documents the canonical sources for generated wrappers and upstream actions" do
    expect(normalized_contributing).to include(
      "copies workflow templates in `lib/github_flow_templates/` into a target repo"
    )
    expect(normalized_documentation).to include(
      "The actions that receive `CPLN_TOKEN_STAGING` come from `shakacode/control-plane-flow` at the commit " \
      "the calling wrapper pins."
    )
    expect(normalized_documentation).to include("### Removing cpflow 6.0.0 action copies")
    expect(normalized_contributing).to include(
      "Edit composite actions in the root `.github/actions/cpflow-*` directories"
    )
  end

  it "consistently requires a protected production deployment ref" do
    expect(normalized_documentation).to include(
      "restrict deployment branches/tags to your protected release branch"
    )
    expect(normalized_documentation).not_to include(
      "optionally disable administrator bypass and restrict deployment branches/tags"
    )
  end
end
