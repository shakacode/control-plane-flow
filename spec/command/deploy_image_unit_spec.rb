# frozen_string_literal: true

require "spec_helper"

describe Command::DeployImage do
  describe "OPTIONS" do
    it "declares --workload as repeatable" do
      workload_option = described_class::OPTIONS.find { |option| option[:name] == :workload }

      expect(workload_option[:params]).to include(type: :string, repeatable: true, aliases: ["-w"])
    end

    it "passes repeated --workload flags through Thor as an array" do
      config = instance_double(Config)
      command = instance_double(described_class, call: true)
      captured_options = nil
      allow(Config).to receive(:new) do |_args, options, _required_options|
        captured_options = options
        config
      end
      allow(described_class).to receive(:new).with(config).and_return(command)
      allow(Cpflow::Cli).to receive(:show_info_header)

      result = run_cpflow_command("deploy-image", "-a", "test-app", "-w", "frontend", "-w", "worker")

      expect(result[:status]).to eq(0), result[:stderr]
      expect(captured_options[:workload]).to eq(%w[frontend worker])
      expect(command).to have_received(:call)
    end
  end

  describe "#resolve_image_to_deploy" do
    def build_command(image_details:, use_digest_image_ref: true)
      image = "test-app:1"
      config = instance_double(Config, app: "test-app", org: "test-org", use_digest_image_ref?: use_digest_image_ref)
      cp = instance_double(Controlplane, latest_image: image, fetch_image_details: image_details)

      command = described_class.new(config)
      allow(command).to receive(:cp).and_return(cp)
      command
    end

    context "when digest mode is enabled" do
      it "returns the latest image with its digest reference" do
        digest = "sha256:#{'a' * 64}"
        command = build_command(image_details: { "digest" => digest })

        expect(command.send(:resolve_image_to_deploy)).to eq("test-app:1@#{digest}")
      end
    end

    context "when digest mode is disabled" do
      it "returns the latest image without validating the digest" do
        command = build_command(
          image_details: { "digest" => "sha512:#{'a' * 128}" },
          use_digest_image_ref: false
        )

        expect(command.send(:resolve_image_to_deploy)).to eq("test-app:1")
      end
    end

    context "when the image does not exist" do
      it "raises the image not found error" do
        command = build_command(image_details: nil)

        expect { command.send(:resolve_image_to_deploy) }
          .to raise_error(/Image 'test-app:1' does not exist in the Docker repository/)
      end
    end

    context "when the image has no digest" do
      it "raises a digest availability error" do
        command = build_command(image_details: { "digest" => nil })

        expect { command.send(:resolve_image_to_deploy) }
          .to raise_error("Image 'test-app:1' does not have a digest available.")
      end
    end

    context "when the image has an empty digest" do
      it "raises a digest availability error" do
        command = build_command(image_details: { "digest" => "" })

        expect { command.send(:resolve_image_to_deploy) }
          .to raise_error("Image 'test-app:1' does not have a digest available.")
      end
    end

    context "when the image has an invalid digest format" do
      it "raises a digest format error" do
        command = build_command(image_details: { "digest" => "sha512:#{'a' * 128}" })

        expect { command.send(:resolve_image_to_deploy) }
          .to raise_error("Unexpected digest format for image 'test-app:1'.")
      end
    end
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  describe "#call" do
    let(:config) do
      instance_double(
        Config,
        app: "test-app",
        org: "test-org",
        location: "aws-us-west-2",
        options: options,
        deploy_order: deploy_order,
        use_digest_image_ref?: false,
        identity: "test-app-identity",
        identity_link: "/org/test-org/gvc/test-app/identity/test-app-identity",
        shared_secret_grants: [
          {
            name: "database",
            secret_name: "shared-database-secrets",
            policy_name: "shared-database-secrets-policy"
          },
          {
            name: "uploads",
            secret_name: "shared-uploads-secrets",
            policy_name: "shared-uploads-secrets-policy"
          }
        ]
      )
    end
    let(:options) { { run_release_phase: run_release_phase } }
    let(:deploy_order) { nil }
    let(:run_release_phase) { false }
    let(:cp) { instance_double(Controlplane) }
    let(:command) { described_class.new(config) }
    let(:workload_data) do
      {
        "name" => "frontend",
        "spec" => {
          "containers" => [
            { "name" => "rails", "image" => "/org/test-org/image/test-app:1" }
          ]
        },
        "status" => { "endpoint" => "https://frontend-test.cpln.app" }
      }
    end

    def policy_data
      {
        "targetKind" => "secret",
        "targetLinks" => ["//secret/shared-database-secrets"],
        "bindings" => []
      }
    end

    before do
      allow(config).to receive(:[]).with(:app_workloads).and_return(["frontend"])
      allow(cp).to receive(:fetch_workload!).with("frontend").and_return(workload_data)
      # fetch_image_details is called for the fail-fast existence check, but the digest
      # value is not consulted because use_digest_image_ref? is false in this describe block.
      allow(cp).to receive_messages(
        latest_image: "test-app:1",
        fetch_image_details: {},
        workload_set_image_ref: true,
        bind_identity_to_policy: true
      )
      allow(cp).to receive(:fetch_policy)
        .with("shared-database-secrets-policy")
        .and_return(policy_data)
      allow(cp).to receive(:fetch_policy)
        .with("shared-uploads-secrets-policy")
        .and_return(uploads_policy_data)
      allow(command).to receive(:cp).and_return(cp)
      allow(Resolv).to receive(:getaddress).and_return("1.2.3.4")
    end

    def uploads_policy_data
      {
        "targetKind" => "secret",
        "targetLinks" => ["//secret/shared-uploads-secrets"],
        "bindings" => []
      }
    end

    it "binds configured shared secret policies before deploying workloads" do
      command.call

      expect(cp).to have_received(:bind_identity_to_policy)
        .with("/org/test-org/gvc/test-app/identity/test-app-identity", "shared-database-secrets-policy")
      expect(cp).to have_received(:bind_identity_to_policy)
        .with("/org/test-org/gvc/test-app/identity/test-app-identity", "shared-uploads-secrets-policy")
    end

    context "when the identity is bound to the shared policy without reveal permission" do
      def policy_data
        {
          "targetKind" => "secret",
          "targetLinks" => ["//secret/shared-database-secrets"],
          "bindings" => [
            {
              "permissions" => %w[view],
              "principalLinks" => ["/org/test-org/gvc/test-app/identity/test-app-identity"]
            }
          ]
        }
      end

      it "adds the reveal binding" do
        command.call

        expect(cp).to have_received(:bind_identity_to_policy)
          .with("/org/test-org/gvc/test-app/identity/test-app-identity", "shared-database-secrets-policy")
      end
    end

    context "when the identity is already bound to the shared policy with reveal permission" do
      def policy_data
        {
          "targetKind" => "secret",
          "targetLinks" => ["//secret/shared-database-secrets"],
          "bindings" => [
            {
              "permissions" => %w[reveal],
              "principalLinks" => ["/org/test-org/gvc/test-app/identity/test-app-identity"]
            }
          ]
        }
      end

      it "does not bind that policy again" do
        command.call

        expect(cp).not_to have_received(:bind_identity_to_policy)
          .with("/org/test-org/gvc/test-app/identity/test-app-identity", "shared-database-secrets-policy")
        expect(cp).to have_received(:bind_identity_to_policy)
          .with("/org/test-org/gvc/test-app/identity/test-app-identity", "shared-uploads-secrets-policy")
      end
    end

    context "when the shared policy returns a fully-qualified secret target link" do
      def policy_data
        {
          "targetKind" => "secret",
          "targetLinks" => ["/org/test-org/secret/shared-database-secrets"],
          "bindings" => []
        }
      end

      it "accepts the policy target" do
        command.call

        expect(cp).to have_received(:bind_identity_to_policy)
          .with("/org/test-org/gvc/test-app/identity/test-app-identity", "shared-database-secrets-policy")
      end
    end

    context "when the shared policy does not target the configured shared secret" do
      def uploads_policy_data
        {
          "targetKind" => "secret",
          "targetLinks" => ["//secret/other-shared-secret"],
          "bindings" => []
        }
      end

      it "raises before granting reveal on the wrong policy" do
        expect { command.call }
          .to raise_error(
            "Shared secret policy 'shared-uploads-secrets-policy' for shared_secret_grants entry " \
            "'uploads' must target only secret 'shared-uploads-secrets'."
          )
        expect(cp).not_to have_received(:bind_identity_to_policy)
      end
    end

    context "when the shared policy also targets another secret" do
      def uploads_policy_data
        {
          "targetKind" => "secret",
          "targetLinks" => ["//secret/shared-uploads-secrets", "//secret/other-shared-secret"],
          "bindings" => []
        }
      end

      it "raises before granting reveal on the broader policy" do
        expect { command.call }
          .to raise_error(
            "Shared secret policy 'shared-uploads-secrets-policy' for shared_secret_grants entry " \
            "'uploads' must target only secret 'shared-uploads-secrets'."
          )
        expect(cp).not_to have_received(:bind_identity_to_policy)
      end
    end

    context "when running a release phase" do
      let(:run_release_phase) { true }

      before do
        allow(config).to receive(:[]).with(:release_script).and_return("bundle exec rails db:migrate")
        allow(command).to receive(:run_release_script)
      end

      it "binds configured shared secret policies before the release script" do
        command.call

        expect(cp).to have_received(:bind_identity_to_policy)
          .with("/org/test-org/gvc/test-app/identity/test-app-identity", "shared-database-secrets-policy")
          .ordered
        expect(command).to have_received(:run_release_script).ordered
      end
    end

    context "when release phase config is invalid" do
      let(:run_release_phase) { true }

      before do
        allow(config).to receive(:[]).with(:release_script).and_raise("Can't find option 'release_script'")
      end

      it "raises before binding shared secret policies" do
        expect { command.call }.to raise_error("Can't find option 'release_script'")
        expect(cp).not_to have_received(:bind_identity_to_policy)
      end
    end

    context "when the requested release phase is blank" do
      let(:run_release_phase) { true }

      before do
        allow(config).to receive(:[]).with(:release_script).and_return(nil)
      end

      it "raises before binding shared secret policies or deploying workloads" do
        expect { command.call }
          .to raise_error("release_script must be configured when --run-release-phase is provided.")
        expect(cp).not_to have_received(:bind_identity_to_policy)
        expect(cp).not_to have_received(:workload_set_image_ref)
      end
    end

    context "when the image preflight fails" do
      before do
        allow(cp).to receive(:fetch_image_details).and_return(nil)
      end

      it "raises before binding shared secret policies" do
        expect { command.call }.to raise_error(/Image 'test-app:1' does not exist/)
        expect(cp).not_to have_received(:bind_identity_to_policy)
      end
    end

    context "when a workload preflight fails" do
      before do
        allow(cp).to receive(:fetch_workload!).with("frontend").and_raise("Workload missing")
      end

      it "raises before binding shared secret policies" do
        expect { command.call }.to raise_error("Workload missing")
        expect(cp).not_to have_received(:bind_identity_to_policy)
      end
    end

    it "shows the workload name in the deploy step message, not the container name" do
      expect { command.call }.to output(/Deploying image 'test-app:1' for workload 'frontend'/).to_stderr
    end

    it "lists the workload name in the deployed endpoints section, not the container name" do
      expect { command.call }.to output(%r{- frontend: https://frontend-test\.cpln\.app}).to_stderr
    end

    it "uses the container name for the API call that updates the image ref" do
      command.call

      expect(cp).to have_received(:workload_set_image_ref)
        .with("frontend", container: "rails", image: "test-app:1")
    end

    it "retries a transient workload image update before recording the deployed endpoint" do
      update_results = [false, true]
      allow(cp).to receive(:workload_set_image_ref) { update_results.shift }
      allow(Kernel).to receive(:sleep)

      expect { command.call }
        .to output(%r{- frontend: https://frontend-test\.cpln\.app}).to_stderr

      expect(cp).to have_received(:workload_set_image_ref)
        .with("frontend", container: "rails", image: "test-app:1").twice
      expect(Kernel).to have_received(:sleep).with(1).once
    end

    it "tolerates workload update propagation beyond the previous 30-second window" do
      update_results = ([false] * 30) + [true]
      allow(cp).to receive(:workload_set_image_ref) { update_results.shift }
      allow(Kernel).to receive(:sleep)

      expect { command.call }
        .to output(%r{- frontend: https://frontend-test\.cpln\.app}).to_stderr

      expect(cp).to have_received(:workload_set_image_ref)
        .with("frontend", container: "rails", image: "test-app:1").exactly(31).times
      expect(Kernel).to have_received(:sleep).with(1).exactly(30).times
    end

    it "does not repeat a successful image update when endpoint resolution fails" do
      progress = StringIO.new
      allow(command).to receive(:progress).and_return(progress)
      allow(Resolv).to receive(:getaddress).and_raise(Resolv::ResolvError)
      allow(cp).to receive(:fetch_workload_deployments)
        .with("frontend")
        .and_return({ "items" => [{ "status" => { "endpoint" => nil } }] })
      allow(Kernel).to receive(:sleep)

      expect { command.call }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(ExitCode::ERROR_DEFAULT) }

      expect(cp).to have_received(:workload_set_image_ref)
        .with("frontend", container: "rails", image: "test-app:1").once
      expect(cp).to have_received(:fetch_workload_deployments).with("frontend").once
      expect(Kernel).not_to have_received(:sleep)
      expect(progress.string).to include("failed!")
      expect(progress.string).not_to include("- frontend:")
    end

    it "fails after the bounded workload image update retry window without recording an endpoint" do
      progress = StringIO.new
      allow(cp).to receive(:workload_set_image_ref).and_return(false)
      allow(command).to receive(:progress).and_return(progress)
      allow(Kernel).to receive(:sleep)

      expect { command.call }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(ExitCode::ERROR_DEFAULT) }

      expect(cp).to have_received(:workload_set_image_ref)
        .with("frontend", container: "rails", image: "test-app:1")
        .exactly(described_class::WORKLOAD_IMAGE_UPDATE_MAX_ATTEMPTS).times
      expect(Kernel).to have_received(:sleep)
        .with(1).at_least(:once)
      expect(progress.string).to include("failed!")
      expect(progress.string).not_to include("- frontend:")
    end

    context "when specific workloads are requested" do
      let(:options) { { run_release_phase: false, workload: ["worker"] } }
      let(:worker_data) do
        {
          "name" => "worker",
          "spec" => {
            "containers" => [
              { "name" => "sidekiq", "image" => "/org/test-org/image/test-app:1" }
            ]
          },
          "status" => { "endpoint" => "https://worker-test.cpln.app" }
        }
      end

      before do
        allow(config).to receive(:[]).with(:app_workloads).and_return(%w[frontend worker])
        allow(cp).to receive(:fetch_workload!).with("worker").and_return(worker_data)
      end

      it "deploys only the requested workloads" do
        command.call

        expect(cp).not_to have_received(:fetch_workload!).with("frontend")
        expect(cp).to have_received(:workload_set_image_ref)
          .with("worker", container: "sidekiq", image: "test-app:1")
        expect(cp).not_to have_received(:workload_set_image_ref)
          .with("frontend", container: "rails", image: "test-app:1")
      end
    end

    context "when a requested workload is not configured" do
      let(:options) { { run_release_phase: false, workload: ["missing"] } }

      it "raises before fetching or deploying workloads" do
        expect { command.call }
          .to raise_error("Workload 'missing' must be listed in app_workloads for app 'test-app'.")
        expect(cp).not_to have_received(:fetch_workload!)
        expect(cp).not_to have_received(:workload_set_image_ref)
      end
    end

    context "when deploy_order is configured" do
      let(:deploy_order) { [["node-renderer"], ["rails"]] }
      let(:node_renderer_data) do
        {
          "name" => "node-renderer",
          "spec" => {
            "containers" => [
              { "name" => "renderer", "image" => "/org/test-org/image/test-app:1" }
            ]
          },
          "status" => { "endpoint" => "https://renderer-test.cpln.app" }
        }
      end
      let(:rails_data) do
        {
          "name" => "rails",
          "spec" => {
            "containers" => [
              { "name" => "rails", "image" => "/org/test-org/image/test-app:1" }
            ]
          },
          "status" => { "endpoint" => "https://rails-test.cpln.app" }
        }
      end
      let(:sidekiq_data) do
        {
          "name" => "sidekiq",
          "spec" => {
            "containers" => [
              { "name" => "worker", "image" => "/org/test-org/image/test-app:1" }
            ]
          },
          "status" => { "endpoint" => "https://sidekiq-test.cpln.app" }
        }
      end

      before do
        allow(config).to receive(:[]).with(:app_workloads).and_return(%w[node-renderer rails sidekiq])
        allow(cp).to receive(:fetch_workload!).with("node-renderer").and_return(node_renderer_data)
        allow(cp).to receive(:fetch_workload!).with("rails").and_return(rails_data)
        allow(cp).to receive(:fetch_workload!).with("sidekiq").and_return(sidekiq_data)
        allow(cp).to receive_messages(workload_suspended?: false, workload_deployments_ready?: true)
      end

      it "deploys ordered groups and waits for each group before deploying the next" do
        events = []
        allow(cp).to receive(:workload_set_image_ref) { |workload, **| events << [:deploy, workload] }
        allow(cp).to receive(:workload_suspended?) do |workload|
          events << [:suspended?, workload]
          false
        end
        allow(cp).to receive(:workload_deployments_ready?) do |workload, **|
          events << [:ready, workload]
          true
        end

        command.call

        expect(events).to eq(
          [
            [:deploy, "node-renderer"],
            [:suspended?, "node-renderer"],
            [:ready, "node-renderer"],
            [:deploy, "rails"],
            [:suspended?, "rails"],
            [:ready, "rails"],
            [:deploy, "sidekiq"],
            [:suspended?, "sidekiq"],
            [:ready, "sidekiq"]
          ]
        )
      end

      it "skips readiness waits for suspended workloads" do
        allow(cp).to receive(:workload_suspended?).with("node-renderer").and_return(true)

        command.call

        expect(cp).not_to have_received(:workload_deployments_ready?)
          .with("node-renderer", location: "aws-us-west-2", expected_status: true)
      end

      it "prints one deployed endpoints summary after all ordered groups finish" do
        expect { command.call }.to output(
          satisfy do |stderr|
            stderr.scan("Deployed endpoints:").size == 1 &&
              stderr.include?("  - node-renderer: https://renderer-test.cpln.app") &&
              stderr.include?("  - rails: https://rails-test.cpln.app") &&
              stderr.include?("  - sidekiq: https://sidekiq-test.cpln.app")
          end
        ).to_stderr
      end

      it "prints deployed endpoints before aborting when an ordered readiness wait fails" do
        allow(command).to receive(:wait_for_workloads_ready) do |group|
          exit(ExitCode::ERROR_DEFAULT) if group == ["rails"]
        end

        expect do
          expect { command.call }
            .to raise_error(SystemExit) { |error| expect(error.status).to eq(ExitCode::ERROR_DEFAULT) }
        end.to output(
          satisfy do |stderr|
            stderr.scan("Deployed endpoints:").size == 1 &&
              stderr.include?("  - node-renderer: https://renderer-test.cpln.app") &&
              stderr.include?("  - rails: https://rails-test.cpln.app") &&
              !stderr.include?("  - sidekiq: https://sidekiq-test.cpln.app")
          end
        ).to_stderr
      end
    end

    context "when specific workloads are requested with deploy_order configured" do
      let(:options) { { run_release_phase: false, workload: ["worker"] } }
      let(:deploy_order) { [["frontend"]] }
      let(:worker_data) do
        {
          "name" => "worker",
          "spec" => {
            "containers" => [
              { "name" => "sidekiq", "image" => "/org/test-org/image/test-app:1" }
            ]
          },
          "status" => { "endpoint" => "https://worker-test.cpln.app" }
        }
      end

      before do
        allow(config).to receive(:[]).with(:app_workloads).and_return(%w[frontend worker])
        allow(cp).to receive(:fetch_workload!).with("worker").and_return(worker_data)
        allow(cp).to receive_messages(workload_suspended?: false, workload_deployments_ready?: true)
      end

      it "lets the explicit workload selection override deploy_order" do
        command.call

        expect(cp).to have_received(:workload_set_image_ref)
          .with("worker", container: "sidekiq", image: "test-app:1")
        expect(cp).not_to have_received(:workload_deployments_ready?)
      end
    end

    context "when a workload has multiple containers matching the app image" do
      let(:workload_data) do
        {
          "name" => "frontend",
          "spec" => {
            "containers" => [
              { "name" => "rails", "image" => "/org/test-org/image/test-app:1" },
              { "name" => "rails-sidecar", "image" => "/org/test-org/image/test-app:1" }
            ]
          },
          "status" => { "endpoint" => "https://frontend-test.cpln.app" }
        }
      end

      it "deploys only the first matching container to avoid duplicate steps per workload" do
        command.call

        expect(cp).to have_received(:workload_set_image_ref)
          .with("frontend", container: "rails", image: "test-app:1").once
        expect(cp).not_to have_received(:workload_set_image_ref)
          .with("frontend", container: "rails-sidecar", image: "test-app:1")
      end
    end

    context "when a workload has no containers matching the app image" do
      let(:workload_data) do
        {
          "name" => "frontend",
          "spec" => {
            "containers" => [
              { "name" => "redis", "image" => "/org/test-org/image/redis:7" }
            ]
          },
          "status" => { "endpoint" => "https://frontend-test.cpln.app" }
        }
      end

      it "does not call the image-update API for the workload" do
        command.call

        expect(cp).not_to have_received(:workload_set_image_ref)
      end

      it "does not list the workload in the deployed endpoints summary" do
        expect { command.call }.not_to output(/- frontend:/).to_stderr
      end
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers
end
