# frozen_string_literal: true

require "spec_helper"

describe Command::ApplyTemplate do
  describe "#skip_existing_secret_resources for a new review app" do
    let(:config) { instance_double(Config, app: "demo-review-pr-97", org: "test-org") }
    let(:cp) { instance_double(Controlplane) }
    let(:command) { described_class.new(config) }

    it "skips an existing generated dictionary without trying to preserve absent workload images" do
      allow(command).to receive(:cp).and_return(cp)
      allow(command).to receive(:report_skipped)
      allow(cp).to receive(:fetch_secret).with("demo-review-pr-97-secrets").and_return({ "type" => "dictionary" })
      secret = { "kind" => "secret", "name" => "demo-review-pr-97-secrets" }
      workload = { "kind" => "workload", "name" => "rails" }

      expect(command.send(:skip_existing_secret_resources, [secret, workload])).to eq([workload])
      expect(command).to have_received(:report_skipped).with(secret)
    end

    it "keeps another pre-existing secret template when only the generated dictionary is skipped" do
      allow(config).to receive(:options).and_return(skip_secret_template: "demo-review-pr-97-secrets")
      allow(command).to receive(:cp).and_return(cp)
      allow(command).to receive(:report_skipped)
      allow(cp).to receive(:fetch_secret)
      generated = { "kind" => "secret", "name" => "demo-review-pr-97-secrets" }
      unrelated = { "kind" => "secret", "name" => "postgres-credentials" }

      result = command.send(:filter_existing_resources, [generated, unrelated])

      expect(result).to eq([unrelated])
      expect(command).to have_received(:report_skipped).with(generated)
      expect(cp).not_to have_received(:fetch_secret)
    end

    it "refuses a missing secret name before applying templates" do
      allow(config).to receive(:options).and_return(skip_secret_template: "")
      allow(command).to receive(:cp).and_return(cp)
      allow(cp).to receive(:fetch_secret)

      expect { command.send(:filter_existing_resources, [{ "kind" => "secret", "name" => "postgres-credentials" }]) }
        .to raise_error(/requires a secret name/)
      expect(cp).not_to have_received(:fetch_secret)
    end

    it "skips only the generated policy and keeps unrelated policies eligible" do
      allow(config).to receive(:options).and_return(skip_policy_template: "demo-review-pr-97-secrets-policy")
      allow(command).to receive(:cp).and_return(cp)
      allow(command).to receive(:report_skipped)
      allow(cp).to receive(:fetch_policy)
      generated = { "kind" => "policy", "name" => "demo-review-pr-97-secrets-policy" }
      unrelated = { "kind" => "policy", "name" => "postgres-policy" }

      expect(command.send(:filter_existing_resources, [generated, unrelated])).to eq([unrelated])
      expect(command).to have_received(:report_skipped).with(generated)
      expect(cp).not_to have_received(:fetch_policy)
    end

    it "refuses an empty policy name before template application" do
      allow(config).to receive(:options).and_return(skip_policy_template: "")
      allow(command).to receive(:cp).and_return(cp)
      allow(cp).to receive(:fetch_policy)

      expect { command.send(:filter_existing_resources, [{ "kind" => "policy", "name" => "other" }]) }
        .to raise_error(/requires a policy name/)
      expect(cp).not_to have_received(:fetch_policy)
    end
  end

  context "when any template does not exist" do
    let!(:app) { dummy_test_app }

    it "raises error" do
      result = run_cpflow_command("apply-template", "app", "rails", "nonexistent", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Missing templates")
      expect(result[:stderr]).to include("- nonexistent")
    end
  end

  context "when all templates exist" do
    let!(:app) { dummy_test_app }

    after do
      run_cpflow_command!("delete", "-a", app, "--yes")
    end

    it "applies valid templates" do
      result = run_cpflow_command("apply-template", "app", "rails", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Created items")
      expect(result[:stderr]).to include("- [app] #{app}")
      expect(result[:stderr]).to include("- [identity] #{app}-identity")
      expect(result[:stderr]).to include("- [workload] rails")
    end

    it "fails to apply invalid templates" do
      result = run_cpflow_command("apply-template", "invalid", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Failed to apply templates")
      expect(result[:stderr]).to include("- [workload] invalid")
    end

    it "applies valid templates and fails to apply invalid templates" do
      result = run_cpflow_command("apply-template", "app", "invalid", "rails", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Created items")
      expect(result[:stderr]).to include("- [app] #{app}")
      expect(result[:stderr]).to include("- [identity] #{app}-identity")
      expect(result[:stderr]).to include("- [workload] rails")
      expect(result[:stderr]).to include("Failed to apply templates")
      expect(result[:stderr]).to include("- [workload] invalid")
    end

    it "replaces all variables correctly" do
      apply_result = run_cpflow_command("apply-template", "app-with-all-variables", "-a", app)
      env_result = run_cpflow_command("env", "-a", app)

      org = dummy_test_org
      location = "aws-us-east-2"
      image = "#{app}:NO_IMAGE_AVAILABLE"
      identity = "#{app}-identity"
      prefix = dummy_test_app_prefix
      expect(apply_result[:status]).to eq(0)
      expect(env_result[:status]).to eq(0)
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

    it "replaces deprecated variables correctly" do
      apply_result = run_cpflow_command("apply-template", "app-with-deprecated-variables", "-a", app)
      env_result = run_cpflow_command("env", "-a", app)

      org = dummy_test_org
      location = "aws-us-east-2"
      image = "#{app}:NO_IMAGE_AVAILABLE"
      expect(apply_result[:status]).to eq(0)
      expect(env_result[:status]).to eq(0)
      expect(env_result[:stdout]).to include("ORG=#{org}")
      expect(env_result[:stdout]).to include("NAME=#{app}")
      expect(env_result[:stdout]).to include("LOCATION=#{location}")
      expect(env_result[:stdout]).to include("IMAGE=#{image}")
    end
  end

  context "when app already exists" do
    let!(:app) { dummy_test_app("default", create_if_not_exists: true) }

    it "asks for confirmation and does nothing" do
      allow(Shell).to receive(:confirm).with(include("App '#{app}' already exists")).and_return(false)

      result = run_cpflow_command("apply-template", "app", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Skipped templates")
      expect(result[:stderr]).to include("- [app] #{app}")
    end

    it "asks for confirmation and re-creates app" do
      allow(Shell).to receive(:confirm).with(include("App '#{app}' already exists")).and_return(true)

      result = run_cpflow_command("apply-template", "app", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Created items")
      expect(result[:stderr]).to include("- [app] #{app}")
    end

    it "skips confirmation and re-creates app" do
      allow(Shell).to receive(:confirm).and_return(false)

      result = run_cpflow_command("apply-template", "app", "-a", app, "--yes")

      expect(Shell).not_to have_received(:confirm)
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Created items")
      expect(result[:stderr]).to include("- [app] #{app}")
    end
  end

  context "when workload already exists" do
    let!(:app) { dummy_test_app("rails", create_if_not_exists: true) }

    it "asks for confirmation and does nothing" do
      allow(Shell).to receive(:confirm).with(include("Workload 'rails' already exists")).and_return(false)

      result = run_cpflow_command("apply-template", "rails", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Skipped templates")
      expect(result[:stderr]).to include("- [workload] rails")
    end

    it "asks for confirmation and re-creates workload" do
      allow(Shell).to receive(:confirm).with(include("Workload 'rails' already exists")).and_return(true)

      result = run_cpflow_command("apply-template", "rails", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Created items")
      expect(result[:stderr]).to include("- [workload] rails")
    end

    it "skips confirmation and re-creates workload" do
      allow(Shell).to receive(:confirm).and_return(false)

      result = run_cpflow_command("apply-template", "rails", "-a", app, "--yes")

      expect(Shell).not_to have_received(:confirm)
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Created items")
      expect(result[:stderr]).to include("- [workload] rails")
    end
  end
end
