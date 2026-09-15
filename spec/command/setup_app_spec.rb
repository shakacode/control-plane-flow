# frozen_string_literal: true

require "spec_helper"

describe Command::SetupApp do
  describe "#call" do
    let(:command) { described_class.new(config) }
    let(:cp) { instance_double(Controlplane) }
    let(:config) do
      instance_double(
        Config,
        app: "test-review-123",
        org: "test-org",
        identity: "test-review-123-identity",
        identity_link: "/org/test-org/gvc/test-review-123/identity/test-review-123-identity",
        secrets: "test-review-secrets",
        secrets_policy: "test-review-secrets-policy",
        generated_review_secret_keys: [],
        options: {},
        current: { skip_secrets_setup: false },
        shared_secret_grants: shared_secret_grants
      )
    end
    let(:shared_secret_grants) do
      [
        {
          name: "database",
          secret_name: "shared-database-secrets",
          policy_name: "shared-database-secrets-policy"
        }
      ]
    end

    before do
      allow(config).to receive(:[]).with(:setup_app_templates).and_return(%w[app rails])
      allow(cp).to receive_messages(fetch_gvc: nil, bind_identity_to_policy: true)
      allow(cp).to receive(:fetch_policy)
        .with("shared-database-secrets-policy")
        .and_return(
          {
            "targetKind" => "secret",
            "targetLinks" => ["//secret/shared-database-secrets"],
            "bindings" => []
          }
        )
      allow(cp).to receive(:reveal_secret)
        .with("shared-database-secrets")
        .and_return("data" => { "password" => "configured-password" })
      allow(command).to receive_messages(cp: cp)
      allow(command).to receive(:create_secret_and_policy_if_not_exist)
      allow(command).to receive(:run_cpflow_command)
    end

    describe "generated review app credentials" do
      let(:config) do
        instance_double(
          Config, app: "demo-review-pr-97", org: "test-org", identity: "demo-review-pr-97-identity",
                  identity_link: "/org/test-org/gvc/demo-review-pr-97/identity/demo-review-pr-97-identity",
                  secrets: "demo-review-pr-97-secrets",
                  secrets_policy: "demo-review-pr-97-secrets-policy",
                  generated_review_secret_keys: %w[SECRET_KEY_BASE RENDERER_PASSWORD]
        )
      end
      let(:cp) { instance_double(Controlplane) }
      let(:command) { described_class.new(config) }

      before do
        allow(command).to receive(:cp).and_return(cp)
        allow(command).to receive(:step) { |_message, &block| block.call }
        allow(cp).to receive(:fetch_secret).with(config.secrets)
        allow(cp).to receive(:apply_hash)
        allow(cp).to receive(:patch_sensitive_secret_data)
        allow(cp).to receive(:fetch_policy)
        allow(cp).to receive(:bind_identity_to_policy)
      end

      it "creates both fields without using the CLI template path" do
        allow(SecureRandom).to receive(:hex).with(32).and_return("a" * 64, "b" * 64)
        allow(cp).to receive(:create_sensitive_secret).and_return(true)

        command.send(:create_secret_if_not_exists)

        expect(cp).to have_received(:create_sensitive_secret).with(
          config.secrets, { "SECRET_KEY_BASE" => "a" * 64, "RENDERER_PASSWORD" => "b" * 64 }
        )
        expect(cp).not_to have_received(:apply_hash)
      end

      it "fills only a missing field and preserves existing values" do
        allow(cp).to receive(:fetch_secret).with(config.secrets).and_return(
          { "name" => config.secrets, "type" => "dictionary",
            "tags" => { Config::GENERATED_REVIEW_APP_TAG => config.app } }
        )
        allow(cp).to receive(:reveal_secret).with(config.secrets).and_return(
          { "type" => "dictionary", "data" => { "SECRET_KEY_BASE" => "existing", "OTHER" => "keep" } }
        )
        allow(SecureRandom).to receive(:hex).with(32).and_return("c" * 64)
        allow(cp).to receive(:patch_sensitive_secret_data).and_return(true)

        command.send(:create_secret_if_not_exists)

        expect(cp).to have_received(:patch_sensitive_secret_data).with(
          config.secrets, { "RENDERER_PASSWORD" => "c" * 64 }
        )
      end

      it "does not rotate populated credentials on refresh" do
        allow(cp).to receive(:fetch_secret).with(config.secrets).and_return(
          { "name" => config.secrets, "type" => "dictionary",
            "tags" => { Config::GENERATED_REVIEW_APP_TAG => config.app } }
        )
        allow(cp).to receive(:reveal_secret).with(config.secrets).and_return(
          { "type" => "dictionary", "data" => { "SECRET_KEY_BASE" => "a", "RENDERER_PASSWORD" => "b" } }
        )

        command.send(:create_secret_if_not_exists)

        expect(cp).not_to have_received(:patch_sensitive_secret_data)
      end

      it "fails closed when the existing dictionary cannot be revealed" do
        allow(cp).to receive(:fetch_secret).with(config.secrets).and_return(
          { "name" => config.secrets, "type" => "dictionary",
            "tags" => { Config::GENERATED_REVIEW_APP_TAG => config.app } }
        )
        allow(cp).to receive(:reveal_secret).with(config.secrets).and_return(nil)

        expect { command.send(:create_secret_if_not_exists) }.to raise_error(/Cannot safely inspect/)
        expect(cp).not_to have_received(:patch_sensitive_secret_data)
      end

      it "refuses to reveal or patch a dictionary owned by another app" do
        allow(cp).to receive(:fetch_secret).with(config.secrets).and_return(
          { "name" => config.secrets, "type" => "dictionary", "tags" => {} }
        )
        allow(cp).to receive(:reveal_secret)

        expect { command.send(:create_secret_if_not_exists) }.to raise_error(/not owned by this app/)
        expect(cp).not_to have_received(:reveal_secret)
        expect(cp).not_to have_received(:patch_sensitive_secret_data)
      end

      it "refuses an existing policy that targets another secret" do
        allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(
          { "targetKind" => "secret", "targetLinks" => ["//secret/foreign"] }
        )

        expect { command.send(:create_policy_if_not_exists) }.to raise_error(/unexpected target or binding/)
        expect(cp).not_to have_received(:apply_hash)
      end

      it "refuses an existing policy bound to another principal" do
        allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(
          { "targetKind" => "secret", "targetLinks" => ["//secret/#{config.secrets}"],
            "bindings" => [{ "principalLinks" => ["/org/test-org/gvc/other/identity/other"] }] }
        )

        expect { command.send(:create_policy_if_not_exists) }.to raise_error(/unexpected target or binding/)
      end

      it "refuses an existing policy with an additional target selector" do
        allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(
          { "targetKind" => "secret", "targetLinks" => ["//secret/#{config.secrets}"],
            "targetQuery" => { "spec" => { "match" => "all" } } }
        )

        expect { command.send(:create_policy_if_not_exists) }.to raise_error(/unexpected target or binding/)
      end

      it "reuses an exact-target policy bound only to this app identity" do
        allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(
          { "targetKind" => "secret", "targetLinks" => ["//secret/#{config.secrets}"],
            "bindings" => [{ "principalLinks" => [config.identity_link], "permissions" => %w[reveal] }] }
        )

        command.send(:create_policy_if_not_exists)

        expect(cp).not_to have_received(:apply_hash)
      end

      it "rechecks policy scope immediately before binding the app identity" do
        allow(cp).to receive(:fetch_policy).with(config.secrets_policy).and_return(
          { "targetKind" => "secret", "targetLinks" => ["//secret/foreign"] }
        )

        expect { command.send(:bind_identity_to_policy) }.to raise_error(/unexpected target or binding/)
        expect(cp).not_to have_received(:bind_identity_to_policy)
      end
    end

    it "binds the app identity to configured shared secret policies" do
      command.call

      expect(cp).to have_received(:bind_identity_to_policy)
        .with(config.identity_link, "test-review-secrets-policy")
      expect(cp).to have_received(:bind_identity_to_policy)
        .with(config.identity_link, "shared-database-secrets-policy")
      expect(cp).to have_received(:reveal_secret).with("shared-database-secrets")
    end

    it "keeps new app setup interactive and runs the post-creation hook path" do
      allow(command).to receive(:run_post_creation_hook)

      command.call

      expect(command).to have_received(:run_cpflow_command)
        .with("apply-template", "app", "rails", "-a", config.app, "--add-app-identity")
      expect(command).to have_received(:run_post_creation_hook)
    end

    context "when refreshing templates for an existing app" do
      before do
        allow(config).to receive(:options).and_return({ refresh_templates: true })
        allow(cp).to receive(:fetch_gvc).and_return({ "name" => config.app })
        allow(command).to receive(:run_post_creation_hook)
      end

      it "applies configured templates noninteractively and repairs secret bindings without running creation hooks" do
        command.call

        expect(command).to have_received(:run_cpflow_command)
          .with(
            "apply-template", "app", "rails", "-a", config.app,
            "--add-app-identity", "--yes", "--preserve-existing-runtime"
          )
        expect(cp).to have_received(:bind_identity_to_policy)
          .with(config.identity_link, "test-review-secrets-policy")
        expect(cp).to have_received(:bind_identity_to_policy)
          .with(config.identity_link, "shared-database-secrets-policy")
        expect(command).not_to have_received(:run_post_creation_hook)
      end

      it "stops when template application fails" do
        allow(command).to receive(:run_cpflow_command).and_raise(SystemExit.new(64))

        expect { command.call }.to raise_error(SystemExit) { |error| expect(error.status).to eq(64) }
        expect(cp).not_to have_received(:bind_identity_to_policy)
      end
    end

    context "when refreshing templates for a missing app" do
      before do
        allow(config).to receive(:options).and_return({ refresh_templates: true })
      end

      it "raises without creating the app" do
        expect { command.call }
          .to raise_error("App 'test-review-123' does not exist, so its templates cannot be refreshed.")
        expect(command).not_to have_received(:create_secret_and_policy_if_not_exist)
        expect(command).not_to have_received(:run_cpflow_command)
      end
    end

    context "when the app already exists without template refresh" do
      before do
        allow(cp).to receive(:fetch_gvc).and_return({ "name" => config.app })
      end

      it "preserves the existing setup error" do
        expect { command.call }.to raise_error(/App 'test-review-123' already exists/)
        expect(command).not_to have_received(:run_cpflow_command)
      end
    end

    context "when a configured shared policy is missing" do
      before do
        allow(cp).to receive(:fetch_policy).with("shared-database-secrets-policy").and_return(nil)
      end

      it "raises before creating app resources" do
        expect { command.call }
          .to raise_error(/Shared secret policy 'shared-database-secrets-policy'/)
        expect(command).not_to have_received(:create_secret_and_policy_if_not_exist)
        expect(command).not_to have_received(:run_cpflow_command)
      end
    end

    context "when a configured shared policy targets the wrong secret" do
      before do
        allow(cp).to receive(:fetch_policy)
          .with("shared-database-secrets-policy")
          .and_return(
            {
              "targetKind" => "secret",
              "targetLinks" => ["//secret/other-secret"],
              "bindings" => []
            }
          )
      end

      it "raises before creating app resources" do
        expect { command.call }
          .to raise_error(
            "Shared secret policy 'shared-database-secrets-policy' for shared_secret_grants entry " \
            "'database' must target only secret 'shared-database-secrets'."
          )
        expect(command).not_to have_received(:create_secret_and_policy_if_not_exist)
        expect(command).not_to have_received(:run_cpflow_command)
      end
    end

    context "when skip_secrets_setup is true" do
      before do
        allow(config).to receive(:options).and_return({ skip_secrets_setup: true })
      end

      it "does not validate or bind shared secret policies" do
        command.call

        expect(cp).not_to have_received(:fetch_policy).with("shared-database-secrets-policy")
        expect(cp).not_to have_received(:reveal_secret).with("shared-database-secrets")
        expect(cp).not_to have_received(:bind_identity_to_policy)
          .with(config.identity_link, "shared-database-secrets-policy")
      end
    end

    context "when skip_secret_access_binding is true" do
      before do
        allow(config).to receive(:options).and_return({ skip_secret_access_binding: true })
      end

      it "does not validate or bind shared secret policies" do
        command.call

        expect(cp).not_to have_received(:fetch_policy).with("shared-database-secrets-policy")
        expect(cp).not_to have_received(:reveal_secret).with("shared-database-secrets")
        expect(cp).not_to have_received(:bind_identity_to_policy)
          .with(config.identity_link, "shared-database-secrets-policy")
      end
    end
  end

  context "when 'setup_app_templates' is not defined" do
    let!(:app) { dummy_test_app("nothing") }

    it "raises error" do
      result = run_cpflow_command("setup-app", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find option 'setup_app_templates'")
    end
  end

  context "when app already exists" do
    let!(:app) { dummy_test_app("default", create_if_not_exists: true) }

    it "raises error" do
      result = run_cpflow_command("setup-app", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("App '#{app}' already exists")
    end
  end

  context "when skipping secrets setup" do
    let!(:app) { dummy_test_app }

    after do
      run_cpflow_command!("delete", "-a", app, "--yes")
    end

    it "applies templates from 'setup_app_templates'" do
      result = run_cpflow_command("setup-app", "-a", app, "--skip-secrets-setup")

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Created items")
      expect(result[:stderr]).to include("[app] #{app}")
      expect(result[:stderr]).to include("[identity] #{app}-identity")
      expect(result[:stderr]).to include("[workload] rails")
      expect(result[:stderr]).to include("[workload] postgres")
      expect(result[:stderr]).not_to include("Failed to apply templates")
      expect(result[:stderr]).not_to include("Binding identity")
    end

    it "works with deprecated --skip-secret-access-binding name" do
      result = run_cpflow_command("setup-app", "-a", app, "--skip-secret-access-binding")

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("DEPRECATED: Option --skip-secret-access-binding is deprecated")
      expect(result[:stderr]).not_to include("Binding identity")
    end
  end

  context "when secret and policy do not exist" do
    let!(:app) { dummy_test_app }
    let!(:app_secrets) { "#{dummy_test_app_prefix}-secrets" }
    let!(:app_secrets_policy) { "#{app_secrets}-policy" }

    after do
      run_cpflow_command!("delete", "-a", app, "--yes")

      api = ControlplaneApi.new
      api.delete_secret(org: dummy_test_org, secret: app_secrets)
      api.delete_policy(org: dummy_test_org, policy: app_secrets_policy)
    end

    it "creates secret and policy, and binds identity to policy" do
      result = run_cpflow_command("setup-app", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Creating secret '#{app_secrets}'[.]+? done!/)
      expect(result[:stderr]).to match(/Creating policy '#{app_secrets_policy}'[.]+? done!/)
      expect(result[:stderr])
        .to match(/Binding identity '#{app}-identity' to policy '#{app_secrets_policy}'[.]+? done!/)
    end
  end

  context "when identity does not exist" do
    let!(:app) { dummy_test_app("nonexistent-identity") }

    after do
      run_cpflow_command!("delete", "-a", app, "--yes")
    end

    it "creates identity, and binds identity to policy" do
      result = run_cpflow_command("setup-app", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("[identity] #{app}-identity")
      expect(result[:stderr]).to include("Secret 'dummy-test-secrets' already exists")
      expect(result[:stderr]).to include("Policy 'dummy-test-secrets-policy' already exists")
      expect(result[:stderr])
        .to match(/Binding identity '#{app}-identity' to policy 'dummy-test-secrets-policy'[.]+? done!/)
    end
  end

  context "when invalid post-creation hook is specified" do
    let!(:app) { dummy_test_app("invalid-post-creation-hook") }

    before do
      run_cpflow_command!("build-image", "-a", app)
    end

    after do
      run_cpflow_command!("delete", "-a", app, "--yes")
    end

    it "fails to run hook", :slow do
      result = run_cpflow_command("setup-app", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Running post-creation hook")
      expect(result[:stderr]).to include("Failed to run post-creation hook")
    end
  end

  context "when valid post-creation hook is specified" do
    let!(:app) { dummy_test_app("valid-post-creation-hook") }

    before do
      run_cpflow_command!("build-image", "-a", app)
    end

    after do
      run_cpflow_command!("delete", "-a", app, "--yes")
    end

    it "successfully runs hook", :slow do
      result = run_cpflow_command("setup-app", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Running post-creation hook")
      expect(result[:stderr]).to include("Finished running post-creation hook")
    end
  end

  context "when skipping post-creation hook" do
    let!(:app) { dummy_test_app("valid-post-creation-hook") }

    after do
      run_cpflow_command!("delete", "-a", app, "--yes")
    end

    it "does not run hook" do
      result = run_cpflow_command("setup-app", "-a", app, "--skip-post-creation-hook")

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).not_to include("Running post-creation hook")
    end
  end

  context "when forwarding org" do
    let!(:app) { dummy_test_app("undefined-org") }

    before do
      stub_env("CPLN_ORG", nil)
    end

    after do
      run_cpflow_command!("delete", "-a", app, "--org", dummy_test_org, "--yes")
    end

    it "forwards org correctly to apply-template" do
      result = run_cpflow_command("setup-app", "-a", app, "--org", dummy_test_org, "--skip-secrets-setup")

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("[app] #{app}")
    end
  end
end
