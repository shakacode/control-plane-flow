# frozen_string_literal: true

require "spec_helper"
require "open3"
require "yaml"

describe "Approved promotion snapshot", :aggregate_failures do # rubocop:disable RSpec/DescribeClass
  let(:sha) { "a" * 40 }
  let(:image) { "app:main_#{sha}@sha256:#{'b' * 64}" }

  def verify_snapshot(preview_image:, current_image:, baseline:, production_image:)
    workflow = YAML.load_file(".github/workflows/cpflow-promote-staging-to-production.yml")
    step = workflow.dig("jobs", "promote-to-production", "steps").find { |item| item["id"] == "verify-preview" }
    env = { "PREVIEW_IMAGE" => preview_image, "CURRENT_STAGING_IMAGE" => current_image,
            "PREVIEW_PRODUCTION_COMMIT" => baseline, "CURRENT_PRODUCTION_IMAGE" => production_image,
            "BASH_ENV" => "/dev/null" }
    Open3.capture3(env, "bash", stdin_data: step.fetch("run"))
  end

  it "allows the exact staging image and recorded production commit" do
    _, _, status = verify_snapshot(preview_image: image, current_image: image, baseline: sha,
                                   production_image: "/org/prod/image/app:v1_#{sha}@sha256:#{'c' * 64}")
    expect(status).to be_success
  end

  it "stops when staging changes while approval is pending" do
    stdout, _, status = verify_snapshot(preview_image: image, current_image: "app:main_#{'d' * 40}",
                                        baseline: sha, production_image: "app:v1_#{sha}")
    expect(status).not_to be_success
    expect(stdout).to include("Staging changed since the preview")
  end

  it "stops when the release record does not describe live production" do
    stdout, _, status = verify_snapshot(preview_image: image, current_image: image, baseline: sha,
                                        production_image: "app:v1_#{'d' * 40}")
    expect(status).not_to be_success
    expect(stdout).to include("Live production does not match")
  end

  it "allows unavailable production provenance without claiming a comparison" do
    _, _, status = verify_snapshot(preview_image: image, current_image: image, baseline: "",
                                   production_image: "app:legacy")
    expect(status).to be_success
  end
end
