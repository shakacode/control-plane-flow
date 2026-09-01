# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "yaml"

RSpec.describe "GitHub workflow definitions" do # rubocop:disable RSpec/DescribeClass
  describe "Review app comment authorization" do
    def workflow_file(name)
      YAML.safe_load_file(File.expand_path("../.github/workflows/#{name}", __dir__), aliases: true)
    end

    {
      "cpflow-deploy-review-app.yml" => "deploy",
      "cpflow-delete-review-app.yml" => "delete-review-app"
    }.each do |workflow_name, command_job_name|
      it "requires write permission before running #{command_job_name} comment commands" do
        workflow = workflow_file(workflow_name)
        authorization_job = workflow.fetch("jobs").fetch("authorize-comment-command")
        permission_step = authorization_job.fetch("steps").find do |step|
          step["name"] == "Resolve comment author repository permission"
        end
        non_comment_step = authorization_job.fetch("steps").find do |step|
          step["name"] == "Allow authenticated non-comment trigger"
        end
        prepare_intent_step = authorization_job.fetch("steps").find do |step|
          step["name"] == "Prepare accepted review app intent"
        end
        record_intent_step = authorization_job.fetch("steps").find do |step|
          step["name"] == "Record accepted review app intent"
        end
        script = permission_step.fetch("run")
        command_job = workflow.fetch("jobs").fetch(command_job_name)

        expect(workflow.fetch("permissions")).to include("actions" => "write", "issues" => "write")
        expect(authorization_job.fetch("permissions")).to eq(
          "actions" => "read",
          "contents" => "read",
          "issues" => "write",
          "pull-requests" => "read"
        )
        expect(authorization_job.fetch("outputs")).to eq(
          "allowed" => "${{ steps.record.outputs.accepted || steps.intent.outputs.reuse }}"
        )
        expect(permission_step).not_to have_key("uses")
        expect(permission_step).to include(
          "shell" => "bash",
          "env" => {
            "GH_TOKEN" => "${{ github.token }}",
            "GH_REPO" => "${{ github.repository }}",
            "COMMENT_AUTHOR" => "${{ github.event.comment.user.login }}"
          }
        )
        expect(script).to include("set -euo pipefail")
        expect(script).to include(%(printf '%s\\n' 'allowed=false' >> "$GITHUB_OUTPUT"))
        expect(script).to include(
          %(gh api --method GET "repos/${GH_REPO}/collaborators/${COMMENT_AUTHOR}/permission" --jq '.permission')
        )
        expect(script).to include("write|maintain|admin)")
        expect(script).to include("read|triage|none)")
        expect(script).to include(%(printf '%s\\n' 'allowed=true' >> "$GITHUB_OUTPUT"))
        expect(script).to include('if [[ -z "${permission}" ]]')
        expect(script).to include("Unexpected repository permission")
        expect(script).not_to include("${{")
        expect(non_comment_step).to include(
          "if" => "github.event_name != 'issue_comment'",
          "run" => include("allowed=true")
        )
        expect(prepare_intent_step).to include(
          "id" => "intent",
          "shell" => "bash",
          "env" => include(
            "GH_TOKEN" => "${{ github.token }}",
            "GH_REPO" => "${{ github.repository }}",
            "RUN_ID" => "${{ github.run_id }}",
            "RECONCILE_INTENT_RUN_ID" => "${{ github.event.inputs.reconcile_intent_run_id }}"
          )
        )
        expected_command = workflow_name.include?("deploy") ? "+review-app-deploy" : "+review-app-delete"
        expected_event = workflow_name.include?("deploy") ? "pull_request'" : "pull_request_target'"
        expect(prepare_intent_step.fetch("if")).to include(expected_command, expected_event, "workflow_dispatch")
        expect(prepare_intent_step.fetch("run")).to include(
          "repos/${GH_REPO}/actions/runs/${RUN_ID}",
          "cpflow-review-app-intent-v1"
        )
        expect(prepare_intent_step.fetch("run")).not_to include("${{")
        expect(record_intent_step).to include(
          "id" => "record",
          "if" => "steps.intent.outputs.record == 'true'",
          "run" => include("repos/${GH_REPO}/issues/${PR_NUMBER}/comments", "accepted=true")
        )
        expect(record_intent_step.fetch("run")).not_to include("${{")
        expect(command_job.fetch("needs")).to eq("authorize-comment-command")
        expect(command_job.fetch("if")).to include(
          "needs.authorize-comment-command.outputs.allowed == 'true'"
        )
        expect(command_job.fetch("if")).not_to include("github.event.comment.author_association")
        expect(workflow).not_to have_key("concurrency")
        expect(command_job.fetch("concurrency")).to include(
          "group" => start_with("cpflow-review-app-"),
          "cancel-in-progress" => false
        )
      end
    end
  end

  describe "RSpec shared workflow" do
    let(:workflow) do
      YAML.safe_load_file(
        File.expand_path("../.github/workflows/rspec-shared.yml", __dir__),
        aliases: true
      )
    end

    let(:job) { workflow.fetch("jobs").fetch("rspec") }

    it "serializes shared-org runs while keeping fast queues per PR (or ref)" do
      # Scheduled, slow, and specific runs that can touch the live domain share
      # one queue. Fast runs remain scoped by PR number (or ref) so unrelated
      # PRs don't share one blocking queue. Queued runs never cancel each other.
      expected_group =
        "cpln-shared-org-${{ vars.CPLN_ORG || github.repository }}-" \
        "${{ inputs.uses_shared_org && 'shared-org' || github.event.pull_request.number || github.ref }}"

      expect(job.fetch("concurrency")).to eq(
        "group" => expected_group,
        "cancel-in-progress" => false
      )
    end
  end

  describe "RSpec workflow callers" do
    def workflow_file(name)
      YAML.safe_load_file(File.expand_path("../.github/workflows/#{name}", __dir__), aliases: true)
    end

    it "marks slow and specific runs as shared-org consumers" do
      rspec_jobs = workflow_file("rspec.yml").fetch("jobs")
      specific_jobs = workflow_file("rspec-specific.yml").fetch("jobs")

      expect(rspec_jobs.fetch("rspec-slow").fetch("with")).to include("uses_shared_org" => true)
      expect(specific_jobs.fetch("rspec-specific").fetch("with")).to include("uses_shared_org" => true)
      expect(rspec_jobs.fetch("rspec-fast").fetch("with")).not_to have_key("uses_shared_org")
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

    let(:deploy_workflow) do
      YAML.safe_load_file(
        File.expand_path("../.github/workflows/cpflow-deploy-review-app.yml", __dir__),
        aliases: true
      )
    end

    let(:deploy_steps) { deploy_workflow.fetch("jobs").fetch("deploy").fetch("steps") }

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

    it "deactivates every GitHub deployment for the deleted review environment" do
      expect(workflow.fetch("permissions")).to include("deployments" => "write")

      step = step_named("Deactivate GitHub review deployments")
      expect(step).to include(
        "id" => "deactivate-deployments",
        "continue-on-error" => true,
        "if" => "steps.config.outputs.ready == 'true' && steps.delete-app.outcome == 'success'",
        "env" => {
          "APP_NAME" => "${{ steps.review-config.outputs.app_name }}"
        }
      )

      script = step.fetch("with").fetch("script")
      expect(script).to include("const environment = `review/${process.env.APP_NAME}`;")
      expect(script).to include("github.paginate(github.rest.repos.listDeployments")
      expect(script).to include("github.rest.repos.listDeploymentStatuses")
      expect(script).to include('latestStatus?.state === "inactive"')
      expect(script).to include("for (const deployment of deployments)")
      expect(script).to include("github.rest.repos.createDeploymentStatus")
      expect(script).to include('state: "inactive"')
    end

    it "reports deployment cleanup failures accurately before failing the workflow" do
      expect(step_named("Delete review app")).to include("id" => "delete-app")

      finalizer = step_named("Finalize delete status")
      expect(finalizer.fetch("env")).to include(
        "DELETE_OUTCOME" => "${{ steps.delete-app.outcome }}",
        "DEACTIVATION_OUTCOME" => "${{ steps.deactivate-deployments.outcome }}"
      )
      expect(finalizer.dig("with", "script")).to include(
        "Review App Deleted, GitHub Deployment Cleanup Failed"
      )

      failure_step = step_named("Fail when GitHub deployment cleanup failed")
      expect(failure_step.fetch("if")).to include("steps.deactivate-deployments.outcome == 'failure'")
      expect(failure_step.fetch("run")).to include("exit 1")
      expect(steps.index(finalizer)).to be < steps.index(failure_step)
    end

    it "serializes deploy and delete workflows in the same per-PR concurrency group" do
      delete_concurrency = workflow.dig("jobs", "delete-review-app", "concurrency")
      deploy_concurrency = deploy_workflow.dig("jobs", "deploy", "concurrency")

      expect(delete_concurrency).to eq(deploy_concurrency)
      expect(delete_concurrency.fetch("group")).to start_with("cpflow-review-app-")
      expect(delete_concurrency.fetch("cancel-in-progress")).to be(false)
    end

    it "creates future review deployments as transient environments" do
      deploy_steps = deploy_workflow.fetch("jobs").fetch("deploy").fetch("steps")
      init_step = deploy_steps.find { |step| step["name"] == "Initialize GitHub deployment" }
      script = init_step.fetch("with").fetch("script")

      expect(script).to include("transient_environment: true")
      expect(script).to include("production_environment: false")
    end

    it "rejects fork sources before checking out or building pull request code" do
      deploy_steps = deploy_workflow.fetch("jobs").fetch("deploy").fetch("steps")
      source_index = deploy_steps.index { |step| step["name"] == "Validate review app deployment source" }
      checkout_index = deploy_steps.index { |step| step["name"] == "Checkout PR commit" }
      build_index = deploy_steps.index { |step| step["name"] == "Build Docker image" }

      expect(source_index).to be < checkout_index
      expect(source_index).to be < build_index
    end

    it "rechecks live PR state after acquiring concurrency and before any deploy step" do
      guard = deploy_steps.find { |step| step["name"] == "Verify pull request is still open" }
      script = guard.fetch("run")

      expect(guard).to include(
        "name" => "Verify pull request is still open",
        "shell" => "bash",
        "env" => {
          "GH_TOKEN" => "${{ github.token }}",
          "GH_REPO" => "${{ github.repository }}"
        }
      )
      expect(script).to include("set -euo pipefail")
      expect(script).to include(
        %(gh api --method GET "repos/${GH_REPO}/pulls/${PR_NUMBER}" --jq '.state')
      )
      expect(script).to include('if [[ "${pr_state}" != "open" ]]')
      expect(script).not_to include("${{")
      expect(deploy_steps.first).to eq(reconciler_step(deploy_steps))
      expect(deploy_steps.index(reconciler_step(deploy_steps))).to be < deploy_steps.index(guard)

      open_result = run_live_pr_guard(script, state: "open")
      closed_result = run_live_pr_guard(script, state: "closed")

      expect(open_result.fetch(:status)).to be_success, open_result.inspect
      expect(closed_result.fetch(:status)).not_to be_success
      expect(closed_result.fetch(:stderr)).to include(
        "Refusing stale review-app deploy because PR #427 is closed."
      )
    end

    it "keeps a redispatched automatic deploy from creating a missing review app" do
      skip_step = deploy_steps.find { |step| step["name"] == "Skip auto deploy until a review app is created" }
      setup_step = deploy_steps.find { |step| step["name"] == "Setup review app if it does not exist yet" }
      missing_app_guard =
        "steps.config.outputs.ready == 'true' && steps.source.outputs.allowed == 'true' && " \
        "steps.check-app.outputs.exists != 'true'"

      expect(skip_step.fetch("if")).to eq(
        "#{missing_app_guard} && steps.intent.outputs.event == 'pull_request'"
      )
      expect(setup_step.fetch("if")).to eq(
        "#{missing_app_guard} && steps.intent.outputs.event != 'pull_request'"
      )
      expect(skip_step.fetch("if")).not_to include("github.event_name")
      expect(setup_step.fetch("if")).not_to include("github.event_name")
    end

    it "rechecks live PR state before an automatic close-triggered deletion" do
      guard = step_named("Verify automatic deletion still targets a closed pull request")
      script = guard.fetch("run")

      expect(guard).to include(
        "name" => "Verify automatic deletion still targets a closed pull request",
        "if" => "steps.intent.outputs.event == 'pull_request_target'",
        "shell" => "bash",
        "env" => {
          "GH_TOKEN" => "${{ github.token }}",
          "GH_REPO" => "${{ github.repository }}"
        }
      )
      expect(script).to include("set -euo pipefail")
      expect(script).to include(
        %(gh api --method GET "repos/${GH_REPO}/pulls/${PR_NUMBER}" --jq '.state')
      )
      expect(script).to include('if [[ "${pr_state}" != "closed" ]]')
      expect(script).not_to include("${{")
      expect(steps.first).to eq(reconciler_step(steps))
      expect(steps.index(reconciler_step(steps))).to be < steps.index(guard)

      closed_result = run_live_pr_guard(script, state: "closed")
      reopened_result = run_live_pr_guard(script, state: "open")

      expect(closed_result.fetch(:status)).to be_success
      expect(reopened_result.fetch(:status)).not_to be_success
      expect(reopened_result.fetch(:stderr)).to include(
        "Refusing stale automatic review-app deletion because PR #427 is open."
      )
    end

    it "records each admitted trigger as a durable bot-owned intent" do
      deploy_prepare = prepare_intent_step(deploy_workflow)
      delete_prepare = prepare_intent_step(workflow)
      deploy_record = record_intent_step(deploy_workflow)
      delete_record = record_intent_step(workflow)
      deploy_script = deploy_prepare.fetch("run")
      delete_script = delete_prepare.fetch("run")

      expect(deploy_prepare.fetch("env")).to include("OPERATION" => "deploy")
      expect(delete_prepare.fetch("env")).to include("OPERATION" => "delete")
      expect(deploy_prepare.fetch("if")).to include(
        "+review-app-deploy",
        "opened",
        "synchronize",
        "reopened",
        "workflow_dispatch"
      )
      expect(delete_prepare.fetch("if")).to include(
        "+review-app-delete",
        "pull_request_target",
        "closed",
        "workflow_dispatch"
      )
      [deploy_script, delete_script].each do |script|
        expect(script).to include(
          "repos/${GH_REPO}/actions/runs/${RUN_ID}",
          "cpflow-review-app-intent-v1",
          "body=${intent_body}",
          "record=true"
        )
        expect(script).not_to include("${{")
      end
      expect(deploy_script).to include("repos/${GH_REPO}/pulls/${PR_NUMBER}", "fork pull requests")
      expect(delete_record.fetch("run")).to eq(deploy_record.fetch("run"))
      expect(deploy_record).to include(
        "id" => "record",
        "if" => "steps.intent.outputs.record == 'true'",
        "run" => include("repos/${GH_REPO}/issues/${PR_NUMBER}/comments", "accepted=true")
      )

      deploy_result = run_record_intent(
        deploy_script,
        deploy_record.fetch("run"),
        operation: "deploy",
        event: "issue_comment"
      )
      delete_result = run_record_intent(
        delete_script,
        delete_record.fetch("run"),
        operation: "delete",
        event: "workflow_dispatch"
      )

      expect(deploy_result.fetch(:status)).to be_success, deploy_result.inspect
      expect(deploy_result.fetch(:stdout)).to include(
        'body=<!-- cpflow-review-app-intent-v1 {"pr":427,"operation":"deploy",' \
        '"event":"issue_comment","actor":"maintainer","run_id":100,' \
        '"created_at":"2026-09-01T05:00:00Z"} -->'
      )
      expect(delete_result.fetch(:status)).to be_success, delete_result.inspect
      expect(delete_result.fetch(:stdout)).to include('"operation":"delete","event":"workflow_dispatch"')
    end

    it "authenticates and reconciles the latest intent before any mutable step" do
      deploy_reconciler = reconciler_step(deploy_steps)
      delete_reconciler = reconciler_step(steps)
      script = deploy_reconciler.fetch("run")
      deploy_reaction = deploy_steps.find { |step| step["name"] == "React to deploy command" }
      delete_reaction = step_named("React to delete command")

      expect(delete_reconciler.fetch("run")).to eq(script)
      expect(deploy_steps.first).to eq(deploy_reconciler)
      expect(steps.first).to eq(delete_reconciler)
      expect(deploy_steps.index(deploy_reconciler)).to be < deploy_steps.index(deploy_reaction)
      expect(steps.index(delete_reconciler)).to be < steps.index(delete_reaction)
      expect(deploy_reconciler).to include(
        "id" => "intent",
        "shell" => "bash",
        "env" => {
          "GH_TOKEN" => "${{ github.token }}",
          "GH_REPO" => "${{ github.repository }}",
          "CURRENT_OPERATION" => "deploy"
        }
      )
      expect(script).to include("gh api --paginate --slurp --method GET")
      expect(script).to include('select(.user.login == "github-actions[bot]")')
      expect(script).to include("repos/${GH_REPO}/actions/runs/${latest_run_id}")
      expect(script).to include("actions/runs/${latest_run_id}/jobs?filter=all&per_page=100")
      expect(script).to include('select(.name == "Record accepted review app intent" and .conclusion == "success")')
      expect(script).to include(".display_title == $title")
      expect(script).to include(".head_repository.full_name == $repo")
      expect(script).to include("write|maintain|admin)")
      expect(script).to include("inputs[reconcile_intent_run_id]=${latest_run_id}")
      expect(script).to include('printf \'event=%s\\n\' "${latest_event}" >> "$GITHUB_OUTPUT"')
      expect(script).not_to include("+review-app-deploy", "+review-app-delete")
      expect(script).not_to include("${{")
    end

    it "redispatches the newest operation when GitHub replaces a pending run" do
      older = intent_payload(operation: "deploy", event: "issue_comment", run_id: 100)
      latest = intent_payload(
        operation: "delete",
        event: "workflow_dispatch",
        run_id: 101,
        created_at: "2026-09-01T05:01:00Z"
      )
      result = run_intent_reconciler(
        reconciler_step(deploy_steps).fetch("run"),
        comments: [intent_comment(older), intent_comment(latest)],
        current_operation: "deploy",
        source_run: actions_run_for(latest)
      )

      expect(result.fetch(:status)).not_to be_success
      expect(result.fetch(:stdout)).to include(
        "actions/workflows/cpflow-delete-review-app.yml/dispatches",
        "inputs[pr_number]=427",
        "inputs[reconcile_intent_run_id]=101"
      )
      expect(result.fetch(:stderr)).to include(
        "Redispatched delete for latest accepted review-app intent run 101."
      )
    end

    it "orders same-second intents by run id and ignores mutable or forged source comments" do
      valid = intent_payload(operation: "deploy", event: "issue_comment", run_id: 101)
      forged = intent_payload(operation: "delete", event: "issue_comment", run_id: 999)
      comments = [
        { "user" => { "login" => "maintainer" }, "body" => "+REVIEW-APP-DELETE" },
        { "user" => { "login" => "maintainer" }, "body" => "+review-app-deploy edited" },
        intent_comment(forged, user: "maintainer"),
        intent_comment(intent_payload(operation: "delete", event: "issue_comment", run_id: 100)),
        intent_comment(valid)
      ]
      result = run_intent_reconciler(
        reconciler_step(deploy_steps).fetch("run"),
        comments: comments,
        current_operation: "deploy",
        source_run: actions_run_for(valid)
      )

      expect(result.fetch(:status)).to be_success, result.inspect
      expect(result.fetch(:stdout)).to include("Applying latest accepted deploy intent from workflow run 101.")
      expect(result.fetch(:stdout)).not_to include("DISPATCH:")
    end

    it "fails closed when the latest manual actor loses permission" do
      older = intent_payload(operation: "deploy", event: "issue_comment", run_id: 100, actor: "still-writer")
      latest = intent_payload(
        operation: "delete",
        event: "issue_comment",
        run_id: 101,
        actor: "revoked",
        created_at: "2026-09-01T05:01:00Z"
      )
      result = run_intent_reconciler(
        reconciler_step(steps).fetch("run"),
        comments: [intent_comment(older), intent_comment(latest)],
        current_operation: "delete",
        permission: "read",
        source_run: actions_run_for(latest)
      )

      expect(result.fetch(:status)).not_to be_success
      expect(result.fetch(:stderr)).to include("actor no longer has permission to run it: read")
      expect(result.fetch(:stdout)).not_to include("Applying latest", "DISPATCH:")
    end

    it "does not apply manual permission lookup semantics to automatic triggers" do
      latest = intent_payload(operation: "delete", event: "pull_request_target", run_id: 101)
      result = run_intent_reconciler(
        reconciler_step(steps).fetch("run"),
        comments: [intent_comment(latest)],
        current_operation: "delete",
        permission: "__FAIL__",
        source_run: actions_run_for(latest)
      )

      expect(result.fetch(:status)).to be_success, result.inspect
      expect(result.fetch(:stdout)).to include("Applying latest accepted delete intent")
    end

    it "rejects bot markers that do not match their originating workflow run" do
      latest = intent_payload(operation: "deploy", event: "issue_comment", run_id: 101)
      mismatched_run = actions_run_for(latest).merge("display_title" => "Deploy Review App - PR #999")
      result = run_intent_reconciler(
        reconciler_step(deploy_steps).fetch("run"),
        comments: [intent_comment(latest)],
        current_operation: "deploy",
        source_run: mismatched_run
      )

      expect(result.fetch(:status)).not_to be_success
      expect(result.fetch(:stderr)).to include("does not match its originating workflow run")
    end

    it "rejects a marker unless the source run successfully posted an accepted intent" do
      latest = intent_payload(operation: "deploy", event: "issue_comment", run_id: 101)
      result = run_intent_reconciler(
        reconciler_step(deploy_steps).fetch("run"),
        comments: [intent_comment(latest)],
        current_operation: "deploy",
        source_run: actions_run_for(latest),
        source_jobs: source_jobs_for(conclusion: "skipped")
      )

      expect(result.fetch(:status)).not_to be_success
      expect(result.fetch(:stderr)).to include("was not emitted by a successful recording step")
    end

    it "rejects cross-PR or fork provenance for automatic deploy intents" do
      latest = intent_payload(operation: "deploy", event: "pull_request", run_id: 101)
      mismatched_run = actions_run_for(latest).merge(
        "pull_requests" => [{ "number" => 999 }],
        "head_repository" => { "full_name" => "outside/fork" }
      )
      result = run_intent_reconciler(
        reconciler_step(deploy_steps).fetch("run"),
        comments: [intent_comment(latest)],
        current_operation: "deploy",
        source_run: mismatched_run
      )

      expect(result.fetch(:status)).not_to be_success
      expect(result.fetch(:stderr)).to include("does not match its originating workflow run")
    end

    it "rejects impossible operation and event combinations" do
      impossible = intent_payload(operation: "delete", event: "pull_request", run_id: 101)
      result = run_intent_reconciler(
        reconciler_step(steps).fetch("run"),
        comments: [intent_comment(impossible)],
        current_operation: "delete",
        source_run: actions_run_for(impossible)
      )

      expect(result.fetch(:status)).not_to be_success
      expect(result.fetch(:stderr)).to include("No accepted review-app intent exists for PR #427.")
    end

    it "fails closed when no valid accepted intent remains" do
      result = run_intent_reconciler(
        reconciler_step(deploy_steps).fetch("run"),
        comments: [{ "user" => { "login" => "maintainer" }, "body" => "+review-app-deploy" }],
        current_operation: "deploy",
        source_run: {}
      )

      expect(result.fetch(:status)).not_to be_success
      expect(result.fetch(:stderr)).to include("No accepted review-app intent exists for PR #427.")
    end

    def run_live_pr_guard(script, state:)
      fake_gh = <<~BASH
        gh() {
          printf '%s\n' "${CPFLOW_TEST_PR_STATE}"
        }
      BASH
      env = { "CPFLOW_TEST_PR_STATE" => state, "GH_REPO" => "shakacode/control-plane-flow", "PR_NUMBER" => "427" }
      stdout, stderr, status = Open3.capture3(env, "/bin/bash", stdin_data: "#{fake_gh}\n#{script}")
      { stdout: stdout, stderr: stderr, status: status }
    end

    def record_intent_step(target_workflow)
      target_workflow.fetch("jobs").fetch("authorize-comment-command").fetch("steps").find do |step|
        step["name"] == "Record accepted review app intent"
      end
    end

    def prepare_intent_step(target_workflow)
      target_workflow.fetch("jobs").fetch("authorize-comment-command").fetch("steps").find do |step|
        step["name"] == "Prepare accepted review app intent"
      end
    end

    def reconciler_step(target_steps)
      target_steps.find { |step| step["name"] == "Reconcile latest accepted review app intent" }
    end

    def intent_payload(operation:, event:, run_id:, actor: "maintainer", created_at: "2026-09-01T05:00:00Z")
      {
        "pr" => 427,
        "operation" => operation,
        "event" => event,
        "actor" => actor,
        "run_id" => run_id,
        "created_at" => created_at
      }
    end

    def intent_comment(payload, user: "github-actions[bot]")
      {
        "user" => { "login" => user },
        "body" => "<!-- cpflow-review-app-intent-v1 #{JSON.generate(payload)} -->"
      }
    end

    def actions_run_for(payload) # rubocop:disable Metrics/MethodLength
      operation_label = payload.fetch("operation") == "deploy" ? "Deploy" : "Delete"
      {
        "id" => payload.fetch("run_id"),
        "event" => payload.fetch("event"),
        "actor" => { "login" => payload.fetch("actor") },
        "created_at" => payload.fetch("created_at"),
        "path" => ".github/workflows/cpflow-#{payload.fetch('operation')}-review-app.yml",
        "display_title" => "#{operation_label} Review App - PR ##{payload.fetch('pr')}",
        "pull_requests" => [{ "number" => payload.fetch("pr") }],
        "head_repository" => { "full_name" => "shakacode/control-plane-flow" }
      }
    end # rubocop:enable Metrics/MethodLength

    def source_jobs_for(conclusion: "success")
      {
        "jobs" => [
          {
            "name" => "deploy / authorize-comment-command",
            "steps" => [
              { "name" => "Record accepted review app intent", "conclusion" => conclusion }
            ]
          }
        ]
      }
    end

    def run_record_intent(prepare_script, record_script, operation:, event:) # rubocop:disable Metrics/MethodLength
      fake_prepare_gh = <<~'BASH'
        gh() {
          case "$*" in
            *'/actions/runs/'*)
              printf '%s\n' "${CPFLOW_TEST_CREATED_AT}"
              ;;
            *'/pulls/'*)
              printf '%s\n' "${GH_REPO}"
              ;;
            *'/comments'*)
              echo "Unexpected early intent post: $*" >&2
              return 1
              ;;
            *)
              echo "Unexpected gh invocation: $*" >&2
              return 1
              ;;
          esac
        }
      BASH
      env = {
        "CPFLOW_TEST_CREATED_AT" => "2026-09-01T05:00:00Z",
        "GH_REPO" => "shakacode/control-plane-flow",
        "PR_NUMBER" => "427",
        "OPERATION" => operation,
        "EVENT_NAME" => event,
        "SOURCE_ACTOR" => "maintainer",
        "RUN_ID" => "100",
        "RECONCILE_INTENT_RUN_ID" => "",
        "GITHUB_OUTPUT" => "/dev/stdout"
      }
      prepare_stdout, prepare_stderr, prepare_status = Open3.capture3(
        env,
        "/bin/bash",
        stdin_data: "#{fake_prepare_gh}\n#{prepare_script}"
      )
      return { stdout: prepare_stdout, stderr: prepare_stderr, status: prepare_status } unless prepare_status.success?

      body_line = prepare_stdout.lines.reverse.find { |line| line.start_with?("body=") }
      intent_body = body_line&.delete_prefix("body=")&.chomp
      fake_record_gh = <<~'BASH'
        gh() {
          printf 'POST:%s\n' "$*"
        }
      BASH
      record_env = env.merge("INTENT_BODY" => intent_body.to_s, "GITHUB_OUTPUT" => "/dev/null")
      stdout, stderr, status = Open3.capture3(
        record_env,
        "/bin/bash",
        stdin_data: "#{fake_record_gh}\n#{record_script}"
      )
      {
        stdout: "#{prepare_stdout}#{stdout}",
        stderr: "#{prepare_stderr}#{stderr}",
        status: status
      }
    end # rubocop:enable Metrics/MethodLength

    def run_intent_reconciler( # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
      script,
      comments:,
      current_operation:,
      source_run:,
      permission: "write",
      source_jobs: nil
    )
      fake_gh = <<~'BASH'
        gh() {
          case "$*" in
            *'/comments?per_page=100'*)
              printf '[%s]\n' "${CPFLOW_TEST_COMMENTS}"
              ;;
            *'/actions/runs/'*'/jobs?filter=all&per_page=100'*)
              printf '[%s]\n' "${CPFLOW_TEST_SOURCE_JOBS}"
              ;;
            *'/actions/runs/'*)
              printf '%s\n' "${CPFLOW_TEST_SOURCE_RUN}"
              ;;
            *'/collaborators/'*)
              [[ "${CPFLOW_TEST_PERMISSION}" != "__FAIL__" ]] || return 1
              printf '%s\n' "${CPFLOW_TEST_PERMISSION}"
              ;;
            *' --jq .default_branch')
              printf '%s\n' main
              ;;
            *'/actions/workflows/'*'/dispatches'*)
              printf 'DISPATCH:%s\n' "$*"
              ;;
            *)
              echo "Unexpected gh invocation: $*" >&2
              return 1
              ;;
          esac
        }
      BASH
      env = {
        "CPFLOW_TEST_COMMENTS" => JSON.generate(comments),
        "CPFLOW_TEST_SOURCE_RUN" => JSON.generate(source_run),
        "CPFLOW_TEST_SOURCE_JOBS" => JSON.generate(source_jobs || source_jobs_for),
        "CPFLOW_TEST_PERMISSION" => permission,
        "GH_REPO" => "shakacode/control-plane-flow",
        "PR_NUMBER" => "427",
        "CURRENT_OPERATION" => current_operation,
        "GITHUB_OUTPUT" => "/dev/null"
      }
      stdout, stderr, status = Open3.capture3(env, "/bin/bash", stdin_data: "#{fake_gh}\n#{script}")
      { stdout: stdout, stderr: stderr, status: status }
    end # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists
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
