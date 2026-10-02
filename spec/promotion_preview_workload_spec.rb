# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "yaml"

describe "Staging preview workload selection" do # rubocop:disable RSpec/DescribeClass
  def resolve_primary(workloads:, requested: "", app: "app-stage") # rubocop:disable Metrics/MethodLength
    action = YAML.load_file(".github/actions/cpflow-preview-promotion/action.yml")
    script = action.dig("runs", "steps").find { |step| step["id"] == "workloads" }.fetch("run")
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p("#{dir}/.controlplane")
      config = { "apps" => { "app-stage" => { "app_workloads" => workloads } } }
      File.write("#{dir}/.controlplane/controlplane.yml", YAML.dump(config))
      output = "#{dir}/output"
      env = { "STAGING_APP_NAME" => app, "PRIMARY_WORKLOAD" => requested,
              "GITHUB_OUTPUT" => output, "BASH_ENV" => "/dev/null" }
      stdout, stderr, status = Open3.capture3(env, "bash", chdir: dir, stdin_data: script)
      [File.exist?(output) ? File.read(output) : "", stdout + stderr, status]
    end
  end

  it "selects staging rails without needing any production Environment variable" do
    output, _, status = resolve_primary(workloads: %w[rails worker])
    expect(status).to be_success
    expect(output).to eq("primary=rails\n")
  end

  it "selects a single non-Rails workload" do
    output, _, status = resolve_primary(workloads: ["web"])
    expect(status).to be_success
    expect(output).to eq("primary=web\n")
  end

  it "uses the shared primary-workload override" do
    output, _, status = resolve_primary(workloads: %w[rails worker], requested: "worker")
    expect(status).to be_success
    expect(output).to eq("primary=worker\n")
  end

  it "rejects an ambiguous default before querying a deployed image" do
    _, message, status = resolve_primary(workloads: %w[web worker])
    expect(status).not_to be_success
    expect(message).to include("PRIMARY_WORKLOAD is not configured")
  end

  it "rejects an override outside staging's workload list" do
    _, message, status = resolve_primary(workloads: ["rails"], requested: "worker")
    expect(status).not_to be_success
    expect(message).to include("not one of")
  end

  it "reports an unknown staging app" do
    _, message, status = resolve_primary(workloads: ["rails"], app: "missing")
    expect(status).not_to be_success
    expect(message).to include("app 'missing' is not defined")
  end
end
