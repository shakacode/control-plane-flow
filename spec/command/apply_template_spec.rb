# frozen_string_literal: true

require "spec_helper"

describe Command::ApplyTemplate do
  context "when any template does not exist" do
    let!(:app) { dummy_test_app }

    it "raises error", :fast do
      result = run_cpl_command("apply-template", "gvc", "rails", "unexistent", "-a", app)

      expect(result[:status]).to eq(1)
      expect(result[:stderr]).to include("Missing templates")
      expect(result[:stderr]).to include("- unexistent")
    end
  end

  context "when all templates exist" do
    let!(:app) { dummy_test_app }

    after do
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "applies valid templates", :fast do
      result = run_cpl_command("apply-template", "gvc", "rails", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Created items")
      expect(result[:stderr]).to include("- [app] #{app}")
      expect(result[:stderr]).to include("- [identity] #{app}-identity")
      expect(result[:stderr]).to include("- [workload] rails")
    end

    it "fails to apply invalid templates", :fast do
      result = run_cpl_command("apply-template", "invalid", "-a", app)

      expect(result[:status]).to eq(1)
      expect(result[:stderr]).to include("Failed to apply templates")
      expect(result[:stderr]).to include("- invalid")
    end

    it "applies valid templates and fails to apply invalid templates", :fast do
      result = run_cpl_command("apply-template", "gvc", "invalid", "rails", "-a", app)

      expect(result[:status]).to eq(1)
      expect(result[:stderr]).to include("Created items")
      expect(result[:stderr]).to include("- [app] #{app}")
      expect(result[:stderr]).to include("- [identity] #{app}-identity")
      expect(result[:stderr]).to include("- [workload] rails")
      expect(result[:stderr]).to include("Failed to apply templates")
      expect(result[:stderr]).to include("- invalid")
    end

    it "replaces all variables correctly", :fast do
      apply_result = run_cpl_command("apply-template", "gvc-with-all-variables", "-a", app)
      env_result = run_cpl_command("env", "-a", app)

      org = dummy_test_org
      location = "aws-us-east-2"
      image = "#{app}:NO_IMAGE_AVAILABLE"
      identity = "#{app}-identity"
      prefix = dummy_test_app_prefix
      expect(apply_result[:status]).to eq(0)
      expect(env_result[:status]).to eq(0)
      expect(apply_result[:stderr]).not_to include("DEPRECATED")
      expect(env_result[:stdout]).to include("ORG=#{org}")
      expect(env_result[:stdout]).to include("NAME=#{app}")
      expect(env_result[:stdout]).to include("LOCATION=#{location}")
      expect(env_result[:stdout]).to include("LOCATION_LINK=/org/#{org}/location/#{location}")
      expect(env_result[:stdout]).to include("IMAGE=#{image}")
      expect(env_result[:stdout]).to include("IMAGE_LINK=/org/#{org}/image/#{image}")
      expect(env_result[:stdout]).to include("IDENTITY=#{identity}")
      expect(env_result[:stdout]).to include("IDENTITY_LINK=/org/#{org}/gvc/#{app}/identity/#{identity}")
      expect(env_result[:stdout]).to include("SECRETS=#{prefix}-secrets")
      expect(env_result[:stdout]).to include("SECRETS_POLICY=#{prefix}-secrets-policy")
    end

    it "replaces deprecated variables correctly and warns about them", :fast do
      apply_result = run_cpl_command("apply-template", "gvc-with-deprecated-variables", "-a", app)
      env_result = run_cpl_command("env", "-a", app)

      org = dummy_test_org
      location = "aws-us-east-2"
      image = "#{app}:NO_IMAGE_AVAILABLE"
      expect(apply_result[:status]).to eq(0)
      expect(env_result[:status]).to eq(0)
      expect(apply_result[:stderr]).to include("DEPRECATED")
      expect(apply_result[:stderr]).to include("APP_ORG -> {{APP_ORG}}")
      expect(apply_result[:stderr]).to include("APP_GVC -> {{APP_NAME}}")
      expect(apply_result[:stderr]).to include("APP_LOCATION -> {{APP_LOCATION}}")
      expect(apply_result[:stderr]).to include("APP_IMAGE -> {{APP_IMAGE}}")
      expect(env_result[:stdout]).to include("ORG=#{org}")
      expect(env_result[:stdout]).to include("NAME=#{app}")
      expect(env_result[:stdout]).to include("LOCATION=#{location}")
      expect(env_result[:stdout]).to include("IMAGE=#{image}")
    end
  end

  context "when app already exists" do
    let!(:app) { dummy_test_app("default", create_if_not_exists: true) }

    it "asks for confirmation and does nothing", :fast do
      allow(Shell).to receive(:confirm).with(include("App '#{app}' already exists")).and_return(false)

      result = run_cpl_command("apply-template", "gvc", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Skipped templates")
      expect(result[:stderr]).to include("- gvc")
    end

    it "asks for confirmation and re-creates app", :fast do
      allow(Shell).to receive(:confirm).with(include("App '#{app}' already exists")).and_return(true)

      result = run_cpl_command("apply-template", "gvc", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Created items")
      expect(result[:stderr]).to include("- [app] #{app}")
    end

    it "skips confirmation and re-creates app", :fast do
      allow(Shell).to receive(:confirm).and_return(false)

      result = run_cpl_command("apply-template", "gvc", "-a", app, "--yes")

      expect(Shell).not_to have_received(:confirm)
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Created items")
      expect(result[:stderr]).to include("- [app] #{app}")
    end
  end

  context "when workload already exists" do
    let!(:app) { dummy_test_app("with-rails", create_if_not_exists: true) }

    it "asks for confirmation and does nothing", :fast do
      allow(Shell).to receive(:confirm).with(include("Workload 'rails' already exists")).and_return(false)

      result = run_cpl_command("apply-template", "rails", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Skipped templates")
      expect(result[:stderr]).to include("- rails")
    end

    it "asks for confirmation and re-creates workload", :fast do
      allow(Shell).to receive(:confirm).with(include("Workload 'rails' already exists")).and_return(true)

      result = run_cpl_command("apply-template", "rails", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Created items")
      expect(result[:stderr]).to include("- [workload] rails")
    end

    it "skips confirmation and re-creates workload", :fast do
      allow(Shell).to receive(:confirm).and_return(false)

      result = run_cpl_command("apply-template", "rails", "-a", app, "--yes")

      expect(Shell).not_to have_received(:confirm)
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Created items")
      expect(result[:stderr]).to include("- [workload] rails")
    end
  end
end
