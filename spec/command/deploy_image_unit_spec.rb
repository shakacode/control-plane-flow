# frozen_string_literal: true

require "spec_helper"

describe Command::DeployImage do
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

  describe "#call" do
    let(:config) do
      instance_double(
        Config,
        app: "test-app",
        org: "test-org",
        options: { run_release_phase: run_release_phase },
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
            "'uploads' must target secret 'shared-uploads-secrets'."
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
            "'uploads' must target secret 'shared-uploads-secrets'."
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
end
