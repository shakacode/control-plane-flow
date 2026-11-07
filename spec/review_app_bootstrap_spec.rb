# frozen_string_literal: true

require "spec_helper"
require "yaml"
require "open3"
require "tmpdir"

RSpec.describe "Review app bootstrap" do # rubocop:disable RSpec/DescribeClass
  let(:steps) do
    YAML.safe_load_file(File.expand_path("../.github/workflows/cpflow-deploy-review-app.yml", __dir__))
        .fetch("jobs").fetch("deploy").fetch("steps")
  end

  it "builds and verifies the PR image before creating or refreshing workloads" do
    build = steps.index { |step| step["id"] == "build-image" }
    resolve = steps.index { |step| step["id"] == "built-image" }
    setup = steps.index { |step| step["id"] == "setup-review-app" }
    refresh = steps.index { |step| step["name"] == "Refresh existing review app templates" }

    expect(resolve).not_to be_nil
    expect(build).to be < resolve
    expect(resolve).to be < setup
    expect(resolve).to be < refresh
    expect(steps[build].fetch("if")).to include("steps.intent.outputs.event != 'pull_request'")
    expect(steps[build].fetch("with").fetch("commit")).to eq("${{ env.PR_SHA }}")
    expect(steps[resolve].fetch("if")).to eq("steps.build-image.outcome == 'success'")
    expect(steps[refresh].fetch("env").fetch("BUILT_IMAGE")).to eq("${{ steps.built-image.outputs.image }}")
    expect(steps[refresh].fetch("run")).to include('--bootstrap-image "${BUILT_IMAGE}"')
  end

  it "accepts only a registry image carrying this app and the exact PR head" do
    script = steps.find { |step| step["id"] == "built-image" }.fetch("run")
    sha = "a" * 40

    Dir.mktmpdir do |directory|
      File.write("#{directory}/cpflow", "#!/bin/sh\nprintf '%s\\n' \"$TEST_IMAGE\"\n")
      File.chmod(0o755, "#{directory}/cpflow")
      env = { "BASH_ENV" => nil, "PATH" => "#{directory}:#{ENV.fetch('PATH')}", "APP_NAME" => "example-pr-123",
              "CPLN_ORG" => "test-org", "PR_SHA" => sha, "GITHUB_OUTPUT" => "#{directory}/output" }

      ["example-pr-123:12_#{sha}", "example-pr-123:12_#{'b' * 40}", "other-app:12_#{sha}",
       "example-pr-123:NO_IMAGE_AVAILABLE"].each_with_index do |image, index|
        File.write(env.fetch("GITHUB_OUTPUT"), "")
        stdout, stderr, status = Open3.capture3(env.merge("TEST_IMAGE" => image), "bash", "-c", script)
        expect(status.success?).to eq(index.zero?), "#{image}: #{stdout}\n#{stderr}"
        expected = index.zero? ? "image=#{image}\n" : ""
        expect(File.read(env.fetch("GITHUB_OUTPUT"))).to eq(expected)
      end

      stdout, stderr, status = Open3.capture3(
        env.merge("TEST_IMAGE" => "example-pr-123:12_abc123", "PR_SHA" => "abc123"), "bash", "-c", script
      )
      expect(status.success?).to be(false), "#{stdout}\n#{stderr}"
    end
  end
end
