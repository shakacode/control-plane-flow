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

  context "when identity or policy does not exist" do
    let!(:app) { dummy_test_app("nonexistent-identity") }

    after do
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "raises error" do
      result = run_cpl_command("setup-app", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't bind identity to policy")
    end
  end

  context "when identity and policy exist" do
    let!(:app) { dummy_test_app }

    before do
      run_cpl_command!("apply-template", "secrets", "-a", app)
    end

    after do
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "binds identity to policy" do
      result = run_cpl_command("setup-app", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Binding identity to policy[.]+? done!/)
    end
  end

  context "when using custom names for secrets" do
    let!(:app) { dummy_test_app }

    before do
      run_cpl_command!("apply-template", "secrets-with-custom-names", "-a", app)
    end

    after do
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "binds identity to policy" do
      result = run_cpl_command("setup-app", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Binding identity to policy[.]+? done!/)
    end
  end
end
