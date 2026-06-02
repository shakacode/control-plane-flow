# frozen_string_literal: true

require "spec_helper"

describe Command::Delete do
  describe "#unbind_identity_from_policy" do
    let(:identity_link) { "/org/test-org/gvc/test-review-123/identity/test-review-123-identity" }
    let(:config) do
      instance_double(
        Config,
        app: "test-review-123",
        identity: "test-review-123-identity",
        identity_link: identity_link,
        secrets_policy: "test-review-secrets-policy",
        shared_secret_grants: [
          {
            name: "database",
            secret_name: "shared-database-secrets",
            policy_name: "shared-database-secrets-policy"
          }
        ]
      )
    end
    let(:cp) { instance_double(Controlplane) }
    let(:command) { described_class.new(config) }

    def app_secret_policy
      {
        "bindings" => [
          {
            "permissions" => %w[reveal],
            "principalLinks" => [identity_link]
          }
        ]
      }
    end

    def shared_secret_policy
      app_secret_policy.merge(
        "targetKind" => "secret",
        "targetLinks" => ["//secret/shared-database-secrets"]
      )
    end

    before do
      allow(command).to receive_messages(cp: cp)
      allow(command).to receive(:step).and_yield
      allow(cp).to receive(:fetch_identity).with("test-review-123-identity").and_return({})
      allow(cp).to receive(:fetch_policy).with("test-review-secrets-policy").and_return(app_secret_policy)
      allow(cp).to receive(:fetch_policy).with("shared-database-secrets-policy").and_return(shared_secret_policy)
      allow(cp).to receive(:unbind_identity_from_policy)
    end

    it "unbinds the app identity from app and shared secret policies" do
      command.send(:unbind_identity_from_policy)

      expect(cp).to have_received(:unbind_identity_from_policy)
        .with(identity_link, "test-review-secrets-policy", permission: "reveal")
      expect(cp).to have_received(:unbind_identity_from_policy)
        .with(identity_link, "shared-database-secrets-policy", permission: "reveal")
    end

    context "when the app secret policy is bound without reveal permission" do
      def app_secret_policy
        {
          "bindings" => [
            {
              "permissions" => %w[view],
              "principalLinks" => [identity_link]
            }
          ]
        }
      end

      def shared_secret_policy
        {
          "targetKind" => "secret",
          "targetLinks" => ["//secret/shared-database-secrets"],
          "bindings" => []
        }
      end

      it "still unbinds the app identity from the app secret policy" do
        command.send(:unbind_identity_from_policy)

        expect(cp).to have_received(:unbind_identity_from_policy)
          .with(identity_link, "test-review-secrets-policy", permission: "view")
        expect(cp).not_to have_received(:unbind_identity_from_policy)
          .with(identity_link, "shared-database-secrets-policy", permission: "reveal")
      end
    end

    context "when shared secret grant config is invalid" do
      before do
        allow(config).to receive(:shared_secret_grants).and_raise("invalid shared_secret_grants")
      end

      it "raises before unbinding the app identity from the app secret policy" do
        expect { command.send(:unbind_identity_from_policy) }
          .to raise_error("invalid shared_secret_grants")
        expect(cp).not_to have_received(:unbind_identity_from_policy)
      end
    end

    context "when the shared policy does not target the configured shared secret" do
      def shared_secret_policy
        app_secret_policy.merge(
          "targetKind" => "secret",
          "targetLinks" => ["//secret/other-shared-secret"]
        )
      end

      it "continues deleting by unbinding the app and drifted shared secret policies" do
        command.send(:unbind_identity_from_policy)

        expect(cp).to have_received(:unbind_identity_from_policy)
          .with(identity_link, "test-review-secrets-policy", permission: "reveal")
        expect(cp).to have_received(:unbind_identity_from_policy)
          .with(identity_link, "shared-database-secrets-policy", permission: "reveal")
      end
    end

    context "when the app secret policy has multiple identity permissions" do
      def app_secret_policy
        {
          "bindings" => [
            {
              "permissions" => %w[reveal view],
              "principalLinks" => [identity_link]
            }
          ]
        }
      end

      def shared_secret_policy
        {
          "targetKind" => "secret",
          "targetLinks" => ["//secret/shared-database-secrets"],
          "bindings" => []
        }
      end

      it "shows the permission in each unbind step message" do
        step_messages = []
        allow(command).to receive(:step) do |message, &block|
          step_messages << message
          block.call
        end

        command.send(:unbind_identity_from_policy)

        expect(step_messages).to contain_exactly(
          "Unbinding identity from policy for app 'test-review-123' (reveal)",
          "Unbinding identity from policy for app 'test-review-123' (view)"
        )
      end
    end

    context "when the shared policy is unbound and does not target the configured shared secret" do
      def shared_secret_policy
        {
          "targetKind" => "secret",
          "targetLinks" => ["//secret/other-shared-secret"],
          "bindings" => []
        }
      end

      it "continues deleting by unbinding only the app secret policy" do
        command.send(:unbind_identity_from_policy)

        expect(cp).to have_received(:unbind_identity_from_policy)
          .with(identity_link, "test-review-secrets-policy", permission: "reveal")
        expect(cp).not_to have_received(:unbind_identity_from_policy)
          .with(identity_link, "shared-database-secrets-policy", permission: "reveal")
      end
    end
  end

  describe "#delete_whole_app" do
    let(:identity_link) { "/org/test-org/gvc/test-review-123/identity/test-review-123-identity" }
    let(:config) do
      instance_double(
        Config,
        app: "test-review-123",
        identity: "test-review-123-identity",
        identity_link: identity_link,
        secrets_policy: "test-review-secrets-policy",
        options: { skip_pre_deletion_hook: false },
        shared_secret_grants: [
          {
            name: "database",
            secret_name: "shared-database-secrets",
            policy_name: "shared-database-secrets-policy"
          }
        ]
      )
    end
    let(:cp) { instance_double(Controlplane) }
    let(:command) { described_class.new(config) }

    before do
      allow(command).to receive_messages(cp: cp)
      allow(command).to receive(:check_volumesets)
      allow(command).to receive(:check_images)
      allow(command).to receive(:confirm_delete).and_return(true)
      allow(command).to receive(:run_pre_deletion_hook)
      allow(command).to receive(:step).and_yield
      allow(command).to receive(:delete_volumesets)
      allow(command).to receive(:delete_gvc)
      allow(command).to receive(:delete_images)
      allow(cp).to receive(:fetch_gvc).and_return({})
      allow(cp).to receive(:fetch_identity).with("test-review-123-identity").and_return({})
      allow(cp).to receive(:fetch_policy).with("test-review-secrets-policy").and_return(app_secret_policy)
      allow(cp).to receive(:fetch_policy).with("shared-database-secrets-policy").and_return(shared_secret_policy)
      allow(cp).to receive(:unbind_identity_from_policy)
    end

    def app_secret_policy
      {
        "bindings" => [
          {
            "permissions" => %w[reveal],
            "principalLinks" => ["/org/test-org/gvc/test-review-123/identity/test-review-123-identity"]
          }
        ]
      }
    end

    def shared_secret_policy
      app_secret_policy.merge(
        "targetKind" => "secret",
        "targetLinks" => ["//secret/other-shared-secret"]
      )
    end

    it "runs the pre-deletion hook before unbinding a bound shared policy target that has drifted" do
      command.send(:delete_whole_app)

      expect(command).to have_received(:run_pre_deletion_hook)
      expect(cp).to have_received(:unbind_identity_from_policy)
        .with(identity_link, "test-review-secrets-policy", permission: "reveal")
      expect(cp).to have_received(:unbind_identity_from_policy)
        .with(identity_link, "shared-database-secrets-policy", permission: "reveal")
    end
  end
end
