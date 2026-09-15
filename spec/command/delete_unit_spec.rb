# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"

describe Command::Delete do
  describe "#unbind_identity_from_policy" do
    let(:identity_link) { "/org/test-org/gvc/test-review-123/identity/test-review-123-identity" }
    let(:config) do
      instance_double(
        Config,
        app: "test-review-123",
        org: "test-org",
        identity: "test-review-123-identity",
        identity_link: identity_link,
        secrets_policy: "test-review-secrets-policy",
        disposable_review_secret_resource_names: nil,
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

    def unbind_identity_from_policy
      command.send(:unbind_identity_from_policy, command.send(:secret_policy_unbinds))
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
      unbind_identity_from_policy

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
        unbind_identity_from_policy

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
        expect { unbind_identity_from_policy }
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
        unbind_identity_from_policy

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

        unbind_identity_from_policy

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
        unbind_identity_from_policy

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
        org: "test-org",
        identity: "test-review-123-identity",
        identity_link: identity_link,
        secrets_policy: "test-review-secrets-policy",
        generated_review_secret_keys: [],
        disposable_review_secret_resource_names: nil,
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
      events = []
      allow(command).to receive(:run_pre_deletion_hook) { events << :hook }
      allow(cp).to receive(:unbind_identity_from_policy) do |_identity_link, policy, permission:|
        events << [:unbind, policy, permission]
      end

      command.send(:delete_whole_app)

      expect(events).to eq(
        [
          :hook,
          [:unbind, "test-review-secrets-policy", "reveal"],
          [:unbind, "shared-database-secrets-policy", "reveal"]
        ]
      )
    end
  end

  describe "disposable review app secret cleanup" do
    let(:config) do
      instance_double(
        Config, app: "demo-review-pr-97", org: "test-org",
                identity_link: "/org/test-org/gvc/demo-review-pr-97/identity/demo-review-pr-97-identity",
                secrets: "demo-review-pr-97-secrets", secrets_policy: "demo-review-pr-97-secrets-policy",
                disposable_review_secret_resource_names:
                  %w[demo-review-pr-97-secrets demo-review-pr-97-secrets-policy],
                generated_review_secret_keys: %w[SECRET_KEY_BASE RENDERER_PASSWORD]
      )
    end
    let(:cp) { instance_double(Controlplane) }
    let(:command) { described_class.new(config) }

    before do
      allow(command).to receive(:cp).and_return(cp)
      allow(command).to receive(:step).and_yield
      allow(cp).to receive(:fetch_secret).with(config.secrets).and_return(
        { "name" => config.secrets, "type" => "dictionary",
          "tags" => { Config::GENERATED_REVIEW_APP_TAG => config.app } }
      )
      allow(cp).to receive(:delete_policy)
      allow(cp).to receive(:delete_secret)
    end

    it "removes a marked dictionary after its policy was already removed" do
      allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(nil)

      command.send(:delete_generated_review_secret_resources)

      expect(cp).to have_received(:delete_secret).with(config.secrets)
      expect(cp).not_to have_received(:delete_policy)
    end

    it "removes marked resources after the generated-key opt-in is removed" do
      allow(config).to receive(:generated_review_secret_keys).and_return([])
      allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(nil)

      command.send(:delete_generated_review_secret_resources)

      expect(cp).to have_received(:delete_secret).with(config.secrets)
    end

    it "unbinds the old per-app policy before GVC deletion after opt-in removal" do
      allow(config).to receive_messages(
        generated_review_secret_keys: [], secrets_policy: "shared-review-policy",
        identity: "demo-review-pr-97-identity",
        identity_link: "/org/test-org/gvc/demo-review-pr-97/identity/demo-review-pr-97-identity",
        shared_secret_grants: []
      )
      allow(cp).to receive(:fetch_identity).with(config.identity).and_return({ "name" => config.identity })
      allow(cp).to receive(:fetch_policy).with("shared-review-policy").and_return(nil)
      allow(cp).to receive(:fetch_policy).with("demo-review-pr-97-secrets-policy").and_return(
        { "targetKind" => "secret", "targetLinks" => ["//secret/demo-review-pr-97-secrets"],
          "tags" => { Config::GENERATED_REVIEW_APP_TAG => config.app },
          "bindings" => [
            { "principalLinks" => [config.identity_link], "permissions" => %w[reveal] }
          ] }
      )
      allow(cp).to receive(:unbind_identity_from_policy)

      command.send(:unbind_identity_from_policy, command.send(:secret_policy_unbinds))

      expect(cp).to have_received(:unbind_identity_from_policy).with(
        config.identity_link, "demo-review-pr-97-secrets-policy", permission: "reveal"
      )
    end

    it "unbinds the marked old policy after its dictionary was already removed" do
      allow(config).to receive_messages(
        generated_review_secret_keys: [], secrets_policy: "shared-review-policy",
        identity: "demo-review-pr-97-identity", shared_secret_grants: []
      )
      allow(cp).to receive(:fetch_identity).with(config.identity).and_return({ "name" => config.identity })
      allow(cp).to receive(:fetch_secret).with(config.secrets).and_return(nil)
      allow(cp).to receive(:fetch_policy).with("shared-review-policy").and_return(nil)
      allow(cp).to receive(:fetch_policy).with("demo-review-pr-97-secrets-policy").and_return(
        { "targetKind" => "secret", "targetLinks" => ["//secret/demo-review-pr-97-secrets"],
          "tags" => { Config::GENERATED_REVIEW_APP_TAG => config.app },
          "bindings" => [{ "principalLinks" => [config.identity_link], "permissions" => %w[reveal] }] }
      )
      allow(cp).to receive(:unbind_identity_from_policy)

      command.send(:unbind_identity_from_policy, command.send(:secret_policy_unbinds))

      expect(cp).to have_received(:unbind_identity_from_policy).with(
        config.identity_link, "demo-review-pr-97-secrets-policy", permission: "reveal"
      )
    end

    it "preserves an unmarked dictionary when its policy is absent" do
      allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(nil)
      allow(cp).to receive(:fetch_secret).with(config.secrets).and_return(
        { "name" => config.secrets, "type" => "dictionary", "tags" => {} }
      )

      expect { command.send(:delete_generated_review_secret_resources) }
        .to raise_error(/leaving secret resources for inspection/)

      expect(cp).not_to have_received(:delete_secret)
      expect(cp).not_to have_received(:delete_policy)
    end

    it "can finish secret cleanup after a prior run already removed the GVC" do
      allow(cp).to receive(:fetch_gvc).and_return(nil)
      allow(command).to receive(:confirm_delete).with("disposable secrets for app #{config.app}").and_return(true)
      allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(
        { "targetKind" => "secret", "targetLinks" => ["//secret/#{config.secrets}"], "bindings" => [],
          "tags" => { Config::GENERATED_REVIEW_APP_TAG => config.app } }
      )

      command.send(:delete_whole_app)

      expect(cp).to have_received(:delete_policy).with(config.secrets_policy)
      expect(cp).to have_received(:delete_secret).with(config.secrets)
    end

    it "unbinds only the deleted app identity when its marked policy outlives the GVC" do
      allow(cp).to receive(:fetch_gvc).and_return(nil)
      allow(command).to receive(:confirm_delete).with("disposable secrets for app #{config.app}").and_return(true)
      bound_policy = {
        "targetKind" => "secret", "targetLinks" => ["//secret/#{config.secrets}"],
        "tags" => { Config::GENERATED_REVIEW_APP_TAG => config.app },
        "bindings" => [{ "principalLinks" => [config.identity_link], "permissions" => %w[reveal] }]
      }
      allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(
        bound_policy, bound_policy, bound_policy.merge("bindings" => [])
      )
      allow(cp).to receive(:unbind_identity_from_policy)

      command.send(:delete_whole_app)

      expect(cp).to have_received(:unbind_identity_from_policy).with(
        config.identity_link, config.secrets_policy, permission: "reveal"
      )
      expect(cp).to have_received(:delete_secret).with(config.secrets)
      expect(cp).to have_received(:delete_policy).with(config.secrets_policy)
    end

    it "does not prompt for a missing plain review app with no disposable resources" do
      allow(config).to receive(:generated_review_secret_keys).and_return([])
      allow(cp).to receive(:fetch_gvc).and_return(nil)
      allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(nil)
      allow(cp).to receive(:fetch_secret).with(config.secrets).and_return(nil)
      allow(command).to receive(:confirm_delete)

      command.send(:delete_whole_app)

      expect(command).not_to have_received(:confirm_delete)
      expect(cp).not_to have_received(:delete_secret)
      expect(cp).not_to have_received(:delete_policy)
    end

    it "reports unsafe retained resources instead of claiming missing-app cleanup succeeded" do
      allow(cp).to receive(:fetch_gvc).and_return(nil)
      allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(
        { "targetKind" => "secret", "targetLinks" => ["//secret/#{config.secrets}"],
          "tags" => { Config::GENERATED_REVIEW_APP_TAG => config.app }, "bindings" => [{}] }
      )
      allow(command).to receive(:confirm_delete)

      expect { command.send(:delete_whole_app) }.to raise_error(/leaving them for inspection/)
      expect(command).not_to have_received(:confirm_delete)
      expect(cp).not_to have_received(:delete_secret)
      expect(cp).not_to have_received(:delete_policy)
    end

    it "deletes only the PR-specific dictionary after an empty exact-target policy" do
      allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(
        { "targetKind" => "secret", "targetLinks" => ["//secret/#{config.secrets}"], "bindings" => [],
          "tags" => { Config::GENERATED_REVIEW_APP_TAG => config.app } }
      )

      command.send(:delete_generated_review_secret_resources)

      expect(cp).to have_received(:delete_policy).with(config.secrets_policy)
      expect(cp).to have_received(:delete_secret).with(config.secrets)
    end

    it "keeps the policy available for retry if dictionary deletion fails" do
      allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(
        { "targetKind" => "secret", "targetLinks" => ["//secret/#{config.secrets}"], "bindings" => [],
          "tags" => { Config::GENERATED_REVIEW_APP_TAG => config.app } }
      )
      allow(cp).to receive(:delete_secret).with(config.secrets).and_raise("transient delete failure")

      expect { command.send(:delete_generated_review_secret_resources) }.to raise_error(/transient delete failure/)
      expect(cp).not_to have_received(:delete_policy)
    end

    it "deletes a marked policy with an empty permission entry for its own identity" do
      allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(
        { "targetKind" => "secret", "targetLinks" => ["//secret/#{config.secrets}"],
          "bindings" => [{ "principalLinks" => [config.identity_link], "permissions" => [] }],
          "tags" => { Config::GENERATED_REVIEW_APP_TAG => config.app } }
      )

      command.send(:delete_generated_review_secret_resources)

      expect(cp).to have_received(:delete_policy).with(config.secrets_policy)
      expect(cp).to have_received(:delete_secret).with(config.secrets)
    end

    it "rejects an empty permission entry for a foreign identity" do
      allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(
        { "targetKind" => "secret", "targetLinks" => ["//secret/#{config.secrets}"],
          "bindings" => [{ "principalLinks" => ["//gvc/foreign/identity/foreign"], "permissions" => [] }],
          "tags" => { Config::GENERATED_REVIEW_APP_TAG => config.app } }
      )

      expect { command.send(:delete_generated_review_secret_resources) }
        .to raise_error(/leaving secret resources for inspection/)

      expect(cp).not_to have_received(:delete_policy)
      expect(cp).not_to have_received(:delete_secret)
    end

    it "leaves the GVC discoverable for stale-app retry when disposable dictionary deletion fails" do
      allow(command).to receive(:delete_volumesets)
      allow(command).to receive(:delete_gvc)
      allow(command).to receive(:delete_images)
      allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(nil)
      allow(cp).to receive(:delete_secret).with(config.secrets).and_raise("transient delete failure")

      expect { command.send(:delete_app_resources) }.to raise_error(/transient delete failure/)
      expect(command).not_to have_received(:delete_gvc)
    end

    it "preserves resources if another binding remains" do
      allow(command).to receive(:delete_volumesets)
      allow(command).to receive(:delete_gvc)
      allow(command).to receive(:delete_images)
      allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(
        { "targetKind" => "secret", "targetLinks" => ["//secret/#{config.secrets}"], "bindings" => [{}],
          "tags" => { Config::GENERATED_REVIEW_APP_TAG => config.app } }
      )

      expect { command.send(:delete_app_resources) }
        .to raise_error(/leaving secret resources for inspection/)

      expect(command).not_to have_received(:delete_gvc)
      expect(cp).not_to have_received(:delete_policy)
      expect(cp).not_to have_received(:delete_secret)
    end

    it "preserves an unmarked policy after its dictionary is already gone" do
      allow(cp).to receive(:fetch_secret).with(config.secrets).and_return(nil)
      allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(
        { "targetKind" => "secret", "targetLinks" => ["//secret/#{config.secrets}"],
          "bindings" => [], "tags" => {} }
      )

      expect { command.send(:delete_generated_review_secret_resources) }
        .to raise_error(/leaving secret resources for inspection/)

      expect(cp).not_to have_received(:delete_policy)
    end

    it "preserves a resource whose provider tags field is explicitly null" do
      allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(nil)
      allow(cp).to receive(:fetch_secret).with(config.secrets).and_return(
        { "name" => config.secrets, "type" => "dictionary", "tags" => nil }
      )

      expect { command.send(:delete_generated_review_secret_resources) }
        .to raise_error(/leaving secret resources for inspection/)

      expect(cp).not_to have_received(:delete_secret)
    end

    it "removes a marked policy after its dictionary was already removed" do
      allow(cp).to receive(:fetch_secret).with(config.secrets).and_return(nil)
      allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(
        { "targetKind" => "secret", "targetLinks" => ["//secret/#{config.secrets}"],
          "bindings" => [], "tags" => { Config::GENERATED_REVIEW_APP_TAG => config.app } }
      )

      command.send(:delete_generated_review_secret_resources)

      expect(cp).to have_received(:delete_policy).with(config.secrets_policy)
    end
  end

  describe "#delete_whole_app through the generated action" do
    it "runs cpflow delete when the GVC is already absent so marked resources can be reconciled" do
      Dir.mktmpdir do |dir|
        cpflow = File.join(dir, "cpflow")
        calls = File.join(dir, "calls")
        File.write(cpflow, <<~SH)
          #!/bin/bash
          printf '%s\\n' "$*" >> "$CALLS_FILE"
          if [[ "$1" == exists ]]; then
            exit 3
          fi
        SH
        File.chmod(0o755, cpflow)

        env = {
          "APP_NAME" => "demo-review-pr-97", "CPLN_ORG" => "test-org",
          "REVIEW_APP_PREFIX" => "demo-review", "CALLS_FILE" => calls,
          "PATH" => "#{dir}:#{ENV.fetch('PATH')}", "BASH_ENV" => nil
        }
        script = Cpflow.root_path.join(".github/actions/cpflow-delete-control-plane-app/delete-app.sh").to_s
        _stdout, stderr, status = Open3.capture3(env, "bash", script)

        expect(status).to be_success, stderr
        expect(File.readlines(calls, chomp: true)).to eq(
          ["exists -a demo-review-pr-97 --org test-org", "delete -a demo-review-pr-97 --org test-org --yes"]
        )
      end
    end
  end
end
