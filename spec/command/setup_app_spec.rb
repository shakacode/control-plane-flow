# frozen_string_literal: true

require "spec_helper"

describe Command::SetupApp do
  context "when 'setup_app_templates' is not defined" do
    let!(:app) { dummy_test_app("nothing") }

    it "raises error" do
      result = run_cpl_command("setup-app", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find option 'setup_app_templates'")
    end
  end

  context "when app already exists" do
    let!(:app) { dummy_test_app("default", create_if_not_exists: true) }

    it "raises error" do
      result = run_cpl_command("setup-app", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("App '#{app}' already exists")
    end
  end

  context "when skipping secret access binding" do
    let!(:app) { dummy_test_app }

    after do
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "applies templates from 'setup_app_templates'" do
      result = run_cpl_command("setup-app", "-a", app, "--skip-secret-access-binding")

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Created items")
      expect(result[:stderr]).to include("[app] #{app}")
      expect(result[:stderr]).to include("[identity] #{app}-identity")
      expect(result[:stderr]).to include("[workload] rails")
      expect(result[:stderr]).to include("[workload] postgres")
      expect(result[:stderr]).not_to include("Failed to apply templates")
    end
  end

  context "when secret and policy do not exist" do
    let!(:app) { dummy_test_app }
    let!(:app_secrets) { "#{dummy_test_app_prefix}-secrets" }
    let!(:app_secrets_policy) { "#{app_secrets}-policy" }

    after do
      run_cpl_command!("delete", "-a", app, "--yes")

      api = ControlplaneApi.new
      api.delete_secret(org: dummy_test_org, secret: app_secrets)
      api.delete_policy(org: dummy_test_org, policy: app_secrets_policy)
    end

    it "creates secret and policy, and binds identity to policy" do
      result = run_cpl_command("setup-app", "-a", app)

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
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "raises error" do
      result = run_cpl_command("setup-app", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Secret 'dummy-test-secrets' already exists")
      expect(result[:stderr]).to include("Policy 'dummy-test-secrets-policy' already exists")
      expect(result[:stderr]).to include("Can't bind identity to policy")
    end
  end

  context "when identity exists" do
    let!(:app) { dummy_test_app("secrets") }

    after do
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "binds identity to policy" do
      result = run_cpl_command("setup-app", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Secret 'dummy-test-secrets' already exists")
      expect(result[:stderr]).to include("Policy 'dummy-test-secrets-policy' already exists")
      expect(result[:stderr])
        .to match(/Binding identity '#{app}-identity' to policy 'dummy-test-secrets-policy'[.]+? done!/)
    end
  end
end
