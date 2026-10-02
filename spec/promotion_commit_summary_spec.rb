# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "yaml"

describe "Production promotion commit summary" do # rubocop:disable RSpec/DescribeClass
  let(:production_sha) { "a" * 40 }
  let(:staging_sha) { "b" * 40 }
  let(:response) do
    {
      status: "ahead", ahead_by: 1, behind_by: 0,
      commits: [{ sha: staging_sha, commit: { message: "Fix checkout\n\nDetails" } }]
    }
  end

  def run_summary(production_image:, staging_image:, response:, api_status: 0) # rubocop:disable Metrics/MethodLength
    workflow = YAML.load_file(".github/workflows/cpflow-promote-staging-to-production.yml")
    step = workflow.dig("jobs", "promote-to-production", "steps").find { |item| item["id"] == "commit-summary" }
    expect(step).not_to be_nil

    Dir.mktmpdir do |dir|
      File.write("#{dir}/gh", "#!/bin/sh\nprintf '%s' \"$TEST_RESPONSE\"\nexit \"$TEST_STATUS\"\n")
      FileUtils.chmod(0o755, "#{dir}/gh")
      env = {
        "PATH" => "#{dir}:#{ENV.fetch('PATH')}", "BASH_ENV" => "/dev/null",
        "PRODUCTION_IMAGE" => production_image, "STAGING_IMAGE" => staging_image,
        "GH_REPO" => "example/app", "GITHUB_SERVER_URL" => "https://github.com",
        "GITHUB_STEP_SUMMARY" => "#{dir}/summary", "TEST_RESPONSE" => JSON.generate(response),
        "TEST_STATUS" => api_status.to_s
      }
      _stdout, stderr, status = Open3.capture3(env, "bash", stdin_data: step.fetch("run"))
      expect(status).to be_success, stderr
      File.read("#{dir}/summary")
    end
  end

  def summary(**overrides)
    run_summary(production_image: "/org/prod/image/app:v1_#{production_sha}",
                staging_image: "stage.registry.cpln.io/app:main_#{staging_sha}@sha256:#{'c' * 64}",
                response: response, **overrides)
  end

  it "shows the deployed image commit range and first-line commit subjects" do
    text = summary
    expect(text).to include("https://github.com/example/app/compare/#{production_sha}...#{staging_sha}")
    expect(text).to include("1 commit(s) on staging that are not on production", "Fix checkout")
    expect(text).not_to include("Details")
  end

  it "reports no commits when the deployed images have the same SHA" do
    expect(summary(staging_image: "app:main_#{production_sha}", api_status: 1)).to include("same commit")
  end

  it "explains unavailable provenance without blocking promotion" do
    expect(summary(production_image: "app:legacy")).to include("Comparison unavailable")
    expect(summary(staging_image: "app:main_bad")).to include("Comparison unavailable")
  end

  it "keeps the compare link when the API cannot resolve the range" do
    expect(summary(api_status: 1)).to include("compare/", "Commit list unavailable")
  end

  it "does not block deployment when the comparison response is incomplete" do
    expect(summary(response: {})).to include("Commit list unavailable")
  end

  it "identifies diverged history instead of implying a simple forward promotion" do
    expect(summary(response: response.merge(status: "diverged", behind_by: 2))).to include("diverged", "2 commit(s)")
  end

  it "identifies staging behind production even when there are no new commits" do
    text = summary(response: response.merge(status: "behind", ahead_by: 0, behind_by: 3, commits: []))
    expect(text).to include("behind", "3 commit(s)")
    expect(text).not_to include("same commit")
  end

  it "escapes commit subjects as text in the HTML list" do
    response[:commits][0][:commit][:message] = "<script>alert(1)</script> [link](https://evil.example)"
    text = summary
    expect(text).to include("&lt;script&gt;", "[link](https://evil.example)")
    expect(text).not_to include("<script>")
  end

  it "bounds the displayed list and links the complete comparison" do
    response[:ahead_by] = 150
    response[:commits] *= 150
    text = summary
    expect(text.scan("<li>").length).to eq(100)
    expect(text).to include("Showing the first 100", "150 commit(s)")
  end
end
