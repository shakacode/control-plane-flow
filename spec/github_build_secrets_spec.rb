# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"

RSpec.describe "GitHub Docker build secrets" do # rubocop:disable RSpec/DescribeClass
  let(:action) do
    YAML.safe_load_file(File.expand_path("../.github/actions/cpflow-build-docker-image/action.yml", __dir__))
  end
  let(:build_cli_script) do
    <<~RUBY
      #!/usr/bin/env ruby
      require "json"
      secrets = ARGV.grep(/\\A--secret=/).to_h do |argument|
        id, path = argument.delete_prefix("--secret=id=").split(",src=", 2)
        [id, File.read(path)]
      end
      File.write(ENV.fetch("BUILD_CAPTURE"), JSON.generate({
        "arguments" => ARGV,
        "secrets" => secrets
      }))
      exit Integer(ENV.fetch("BUILD_STATUS", "0"))
    RUBY
  end
  let(:steps) { action.fetch("runs").fetch("steps") }
  let(:directory) { Dir.mktmpdir("cpflow build secrets ") }
  let(:bin) { File.join(directory, "bin") }

  def build_environment # rubocop:disable Metrics/MethodLength
    {
      "PATH" => "#{bin}:#{ENV.fetch('PATH')}",
      "BUILD_CAPTURE" => File.join(directory, "capture.json"),
      "BUILD_STATUS" => "0",
      "APP_NAME" => "test-app",
      "COMMIT_SHA" => "a" * 40,
      "CONTROL_PLANE_ORG" => "test-org",
      "DOCKER_BUILD_EXTRA_ARGS" => "",
      "PR_NUMBER" => "",
      "CPFLOW_BUILD_SSH_PREPPED" => "false",
      "WORKING_DIRECTORY" => directory,
      "DOCKER_BUILD_SECRET_DIRECTORY" => secret_directory
    }
  end

  after do
    FileUtils.remove_entry(directory)
  end

  def step(name)
    steps.find { |entry| entry["name"] == name }
  end

  def prepare(secrets)
    environment = {
      "RUNNER_TEMP" => directory,
      "GITHUB_OUTPUT" => File.join(directory, "outputs"),
      "DOCKER_BUILD_SECRETS" => secrets
    }
    Open3.capture3(
      environment,
      "bash", "-c", step("Prepare Docker build secrets").fetch("run")
    )
  end

  def secret_directory
    File.readlines(File.join(directory, "outputs"), chomp: true)
        .find { |line| line.start_with?("directory=") }.delete_prefix("directory=")
  end

  def build(overrides = {})
    FileUtils.mkdir_p(bin)
    File.write(File.join(bin, "cpflow"), build_cli_script)
    FileUtils.chmod(0o755, File.join(bin, "cpflow"))
    Open3.capture3(
      build_environment.merge(overrides),
      "bash", "-c", step("Build Docker image").fetch("run")
    )
  end

  it "exposes an optional build-secret input" do
    expect(action.fetch("inputs")).to include("docker_build_secrets" => include("required" => false))
  end

  it "passes secrets through both reusable workflows and generated callers" do
    %w[staging review-app].each do |name|
      path = File.expand_path("../.github/workflows/cpflow-deploy-#{name}.yml", __dir__)
      workflow = YAML.safe_load_file(path)
      triggers = workflow["on"] || workflow.fetch(true)
      expect(triggers.dig("workflow_call", "inputs", "docker_build_extra_args"))
        .to include(
          "required" => false,
          "type" => "string",
          "default" => ""
        )
      expect(triggers.dig("workflow_call", "secrets", "DOCKER_BUILD_SECRETS"))
        .to include("required" => false)
      build_step = workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }
                                                .find { |entry| entry["name"] == "Build Docker image" }
      expect(build_step.dig("with", "docker_build_extra_args"))
        .to eq("${{ vars.DOCKER_BUILD_EXTRA_ARGS }}\n${{ inputs.docker_build_extra_args }}\n")
      expect(build_step.dig("with", "docker_build_secrets")).to eq("${{ secrets.DOCKER_BUILD_SECRETS }}")
      caller_path = File.expand_path("../lib/github_flow_templates/.github/workflows/cpflow-deploy-#{name}.yml",
                                     __dir__)
      caller = YAML.safe_load_file(caller_path)
      caller_job = caller.fetch("jobs").values.find { |job| job["uses"] }
      repository_secret = name == "review-app" ? "REVIEW_APP_DOCKER_BUILD_SECRETS" : "DOCKER_BUILD_SECRETS"
      expect(caller_job.dig("secrets", "DOCKER_BUILD_SECRETS")).to eq("${{ secrets.#{repository_secret} }}")
    end
  end

  it "preserves secret values and uses private temporary files" do
    stdout, stderr, status = prepare("sentry_auth_token=test-secret=with-equals\r\nsecond= leading and trailing \n")

    expect(status).to be_success, stderr
    expect(stdout.lines.grep_v(/\A::add-mask::/).join + stderr).not_to include("test-secret")
    expect(File.read(File.join(secret_directory, "sentry_auth_token"))).to eq("test-secret=with-equals")
    expect(File.read(File.join(secret_directory, "second"))).to eq(" leading and trailing ")
    expect(File.stat(secret_directory).mode & 0o777).to eq(0o700)
    expect(File.stat(File.join(secret_directory, "sentry_auth_token")).mode & 0o777).to eq(0o600)
  end

  it "registers extracted secret values for masking with workflow-command escaping" do
    stdout, stderr, status = prepare("token=test%0D\rvalue=with-equals\nsecond= leading and trailing \n")

    expect(status).to be_success, stderr
    expect(stdout).to eq("::add-mask::test%250D%0Dvalue=with-equals\n::add-mask:: leading and trailing \n")
    expect(stderr).to be_empty
    expect(File.read(File.join(secret_directory, "token"))).to eq("test%0D\rvalue=with-equals")
    expect(File.read(File.join(secret_directory, "second"))).to eq(" leading and trailing ")
  end

  it "passes only secret file paths to the build and cleans up after success" do
    expect(prepare("sentry_auth_token=test-secret").last).to be_success
    prepared_directory = secret_directory
    stdout, stderr, status = build

    expect(status).to be_success, stderr
    capture = JSON.parse(File.read(File.join(directory, "capture.json")))
    expect(capture.fetch("secrets")).to eq("sentry_auth_token" => "test-secret")
    expect(capture.fetch("arguments")).to include("--commit=#{'a' * 40}")
    expect(stdout + stderr + capture.fetch("arguments").join).not_to include("test-secret")
    expect(File).not_to exist(prepared_directory)
  end

  it "cleans up secrets after build failure and before-build argument failures" do
    [
      { "BUILD_STATUS" => "1" },
      { "DOCKER_BUILD_EXTRA_ARGS" => "--build-arg BAD" },
      { "WORKING_DIRECTORY" => "missing-directory" }
    ].each do |overrides|
      expect(prepare("sentry_auth_token=test-secret").last).to be_success
      prepared_directory = secret_directory
      _stdout, _stderr, status = build(overrides)

      expect(status).not_to be_success
      expect(File).not_to exist(prepared_directory)
      File.delete(File.join(directory, "outputs"))
    end
  end

  it "rejects malformed, empty, and duplicate entries without leaking or retaining values" do
    [
      "../escape=test-secret",
      "invalid entry=test-secret",
      "missing-equals-test-secret",
      "empty=",
      "duplicate=test-secret\nduplicate=another"
    ].each do |secrets|
      stdout, stderr, status = prepare(secrets)

      expect(status).not_to be_success
      expect(stdout.lines.grep_v(/\A::add-mask::/).join + stderr).not_to include("test-secret")
      expect(Dir.glob(File.join(directory, "cpflow-build-secrets.*"))).to be_empty
    end
  end

  it "runs final cleanup even when an earlier composite step fails" do
    expect(prepare("sentry_auth_token=test-secret").last).to be_success
    prepared_directory = secret_directory
    cleanup = step("Clean up Docker build secrets")
    expect(cleanup.fetch("if")).to include("always()")
    _stdout, stderr, status = Open3.capture3(
      { "DOCKER_BUILD_SECRET_DIRECTORY" => prepared_directory },
      "bash", "-c", cleanup.fetch("run")
    )

    expect(status).to be_success, stderr
    expect(File).not_to exist(prepared_directory)
  end
end
