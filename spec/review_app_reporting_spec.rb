# frozen_string_literal: true

require "spec_helper"
require "open3"
require "yaml"

describe "Review app deployment reporting" do # rubocop:disable RSpec/DescribeClass
  let(:workflow) do
    YAML.safe_load_file(Cpflow.root_path.join(".github/workflows/cpflow-deploy-review-app.yml"), aliases: true)
  end
  let(:steps) { workflow.fetch("jobs").fetch("deploy").fetch("steps") }

  it "uses a runner with binaries for application Ruby versions" do
    expect(workflow.dig("jobs", "deploy", "runs-on")).to eq("ubuntu-24.04")
    %w[cpflow-delete-review-app.yml cpflow-cleanup-stale-review-apps.yml].each do |filename|
      lifecycle = YAML.safe_load_file(Cpflow.root_path.join(".github/workflows", filename), aliases: true)
      expect(lifecycle.fetch("jobs").values.first.fetch("runs-on")).to eq("ubuntu-24.04")
    end
  end

  it "records the attempt before environment setup can fail" do
    setup_index = steps.index { |step| step["name"] == "Setup environment" }
    expect(steps.index { |step| step["id"] == "init-deployment" }).to be < setup_index
  end

  it "publishes a failure when environment setup fails before the app exists" do
    result = report(status: "failure", exists: false)

    expect(result.fetch("statuses").last).to include("state" => "failure", "log_url" => include("/actions/runs/123"))
    expect(result.fetch("comments").last).to include("Failed", "427", "abc123")
  end

  it "publishes cancellation when a deployment is canceled before provisioning" do
    result = report(status: "cancelled", exists: false)

    expect(result.fetch("statuses").last).to include("state" => "failure")
    expect(result.fetch("comments").last).to include("Cancelled", "427")
  end

  it "links the healthy preview on successful deployment" do
    result = report(status: "success", exists: true, url: "https://preview.example.test")

    expect(result.fetch("statuses").last).to include(
      "state" => "success", "environment_url" => "https://preview.example.test"
    )
    expect(result.fetch("comments").last).to include("https://preview.example.test")
  end

  it "does not advertise a ready preview when automatic deployment was skipped" do
    result = report(status: "success", exists: false, event: "pull_request", tracked: false)

    expect(result.fetch("statuses")).to be_empty
    expect(result.fetch("comments")).to be_empty
  end

  it "retains success for an automatic update of an existing review app" do
    result = report(status: "success", exists: true, event: "pull_request", url: "https://preview.example.test")

    expect(result.fetch("statuses").last).to include("state" => "success")
    expect(result.fetch("comments").last).to include("Deploy Complete!")
  end

  it "reports an automatic update failure on the PR even before app detection" do
    result = report(status: "failure", exists: false, event: "pull_request")

    expect(result.fetch("statuses").last).to include("state" => "failure")
    expect(result.fetch("comments").last).to include("Failed")
  end

  it "links config-resolution failures without publishing an unnamed deployment" do
    result = report(status: "failure", exists: false, configured: false)

    expect(result.fetch("statuses")).to be_empty
    expect(result.fetch("comments").last).to include("Failed", "https://github.com/example/app/actions/runs/123")
    expect(result.fetch("comments").last).not_to include("Console", "]()")
  end

  it "does not report an early automatic failure on an unrelated PR" do
    result = report(status: "failure", exists: false, event: "pull_request", tracked: false)

    expect(result.fetch("statuses")).to be_empty
    expect(result.fetch("comments")).to be_empty
  end

  it "does not label a missing preview URL as ready" do
    result = report(status: "success", exists: true)

    expect(result.fetch("statuses").last).to include("state" => "failure")
  end

  it "publishes an automatic attempt in progress before setup fails" do
    result = report(status: "failure", exists: true, event: "pull_request")

    expect(result.fetch("statuses").first).to include("state" => "in_progress")
  end

  it "does not track stale metadata for an app removed outside the delete workflow" do
    result = report(status: "failure", exists: false, event: "pull_request", tracked: true, live: false)

    expect(result.fetch("statuses")).to be_empty
    expect(result.fetch("comments")).to be_empty
  end

  it "deactivates an automatic attempt if the app disappears after the early lookup" do
    result = report(status: "success", exists: false, event: "pull_request", live: true)

    expect(result.fetch("statuses").map { |item| item.fetch("state") }).to eq(%w[in_progress inactive])
    expect(result.fetch("comments")).to be_empty
  end

  it "accepts an already prefixed Control Plane token" do
    result = report(status: "failure", exists: true, event: "pull_request", token: "Bearer fixture-token")

    expect(result.fetch("statuses").first).to include("state" => "in_progress")
  end

  def report(status:, exists:, url: "", event: "issue_comment", **scenario)
    input = { steps: reporting_steps(scenario.fetch(:configured, true)), status:, exists:, url:, event:,
              configured: true, tracked: true }.merge(scenario)
    stdout, stderr, process = Open3.capture3("node", "-e", node_runner, stdin_data: JSON.generate(input))
    expect(process).to be_success, stderr
    JSON.parse(stdout)
  end

  def reporting_steps(configured)
    selected = steps.select do |step|
      ["Find tracked review deployment", "Create initial PR comment", "Set deployment links",
       "Initialize GitHub deployment", "Finalize deployment status"].include?(step["name"])
    end
    configured ? selected : selected.select { |step| step["name"] == "Finalize deployment status" }
  end

  def node_runner
    <<~'JS'
      const fs = require('fs');
      const input = JSON.parse(fs.readFileSync(0, 'utf8'));
      const outputs = {};
      const comments = [];
      const statuses = [];
      const context = {repo: {owner: 'example', repo: 'app'}, runId: 123};
      const env = {CPLN_TOKEN: input.token || 'fixture-token', PR_NUMBER: '427', PR_SHA: 'abc123', APP_NAME: 'app-review-427',
        CPLN_ORG: 'staging', GITHUB_SERVER_URL: 'https://github.com', JOB_STATUS: input.status,
        APP_URL: input.url, INTENT_EVENT: input.event, CHECK_APP_EXISTS: String(input.exists)};
      if (!input.configured) {env.APP_NAME = ''; env.CPLN_ORG = ''; env.WORKFLOW_URL = ''; env.CONSOLE_URL = '';}
      Object.assign(process.env, env);
      const steps = {config: {outputs: {ready: 'true'}}, source: {outputs: {allowed: 'true'}},
        'check-app': {outputs: {exists: String(input.exists)}},
        'setup-review-app': {outcome: input.exists ? 'success' : 'skipped'},
        intent: {outputs: {event: input.event}}};
      const core = {setOutput: (key, value) => {outputs[key] = value;},
        exportVariable: (key, value) => {process.env[key] = value;}, warning: () => {}};
      const github = {rest: {issues: {
        createComment: async data => {comments.push(data.body); return {data: {id: 1}};},
        updateComment: async data => {comments.push(data.body);}
      }, repos: {
        createDeployment: async () => ({data: {id: 2}}),
        createDeploymentStatus: async data => {statuses.push(data);}
      }}};
      const fetch = async (url, options) => {
        if (url !== 'https://api.cpln.io/org/staging/gvc/app-review-427' ||
            options.headers.Authorization !== 'Bearer fixture-token') throw new Error('Unexpected lookup request');
        return {status: (input.live ?? input.tracked) ? 200 : 404};
      };
      (async () => {
        for (const step of input.steps) {
          const expression = (step.if || 'true').replace(/steps\.([\w-]+)/g, (_, key) => `steps[${JSON.stringify(key)}]`);
          if (!Function('steps', 'always', `return ${expression}`)(steps, () => true)) continue;
          steps["tracked-deployment"] = {outputs: {tracked: outputs.tracked || ""}};
          process.env.REVIEW_APP_TRACKED = outputs.tracked || '';
          process.env.COMMENT_ID = outputs['comment-id'] || '';
          process.env.DEPLOYMENT_ID = outputs.result || '';
          const result = await new Function('github', 'context', 'core', 'fetch', `return (async () => {${step.with.script}})()`)(github, context, core, fetch);
          if (step.id === 'init-deployment') outputs.result = String(result);
        }
        process.stdout.write(JSON.stringify({comments, statuses}));
      })().catch(error => {console.error(error); process.exit(1);});
    JS
  end
end
