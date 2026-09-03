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
    expect(normalized_documentation).to include("cannot validate unmerged wrappers or local actions")
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

  it "documents both canonical sources for generated GitHub flow files" do
    expect(normalized_contributing).to include(
      "workflow templates in `lib/github_flow_templates/` and canonical composite actions in " \
      "`.github/actions/cpflow-*`"
    )
    expect(normalized_contributing).to include(
      "Edit composite actions in the root `.github/actions/cpflow-*` directories"
    )
  end
end
