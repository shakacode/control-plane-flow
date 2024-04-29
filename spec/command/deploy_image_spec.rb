# frozen_string_literal: true

require "spec_helper"

describe Command::DeployImage do
  context "when image does not exist" do
    let!(:app) { dummy_test_app("with-rails", create_if_not_exists: true) }

    it "raises error" do
      result = run_cpl_command("deploy-image", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to match(/Image '#{app}:NO_IMAGE_AVAILABLE' does not exist/)
    end
  end

  context "when any app workload does not exist" do
    let!(:app) { dummy_test_app }

    before do
      run_cpl_command!("apply-template", "gvc", "-a", app)
      run_cpl_command!("build-image", "-a", app)
    end

    after do
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "raises error", :slow do
      result = run_cpl_command("deploy-image", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find workload 'rails'")
    end
  end

  context "when not running release phase" do
    let!(:app) { dummy_test_app("with-rails-with-non-app-image", create_if_not_exists: true) }

    it "deploys latest image to app workloads", :slow do
      result = run_cpl_command("deploy-image", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).not_to include("Running release script")
      expect(result[:stderr]).to match(%r{- rails: https://rails-.+?.cpln.app})
      expect(result[:stderr]).not_to include("- rails-with-non-app-image:")
    end
  end

  context "when 'release_script' is not defined" do
    let!(:app) { dummy_test_app("with-nothing") }

    it "raises error" do
      result = run_cpl_command("deploy-image", "-a", app, "--run-release-phase")

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find option 'release_script'")
    end
  end

  context "when release script does not exist" do
    let!(:app) { dummy_test_app("with-nonexistent-release-script") }

    it "raises error" do
      result = run_cpl_command("deploy-image", "-a", app, "--run-release-phase")

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find release script")
    end
  end

  context "when release script is invalid" do
    let!(:app) { dummy_test_app("with-invalid-release-script") }

    before do
      ENV["APP_NAME"] = app

      allow(Kernel).to receive(:sleep)

      run_cpl_command!("apply-template", "gvc", "rails", "-a", app)
      run_cpl_command!("build-image", "-a", app)
    end

    after do
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "fails to run release script and fails to deploy image", :slow do
      result = run_cpl_command("deploy-image", "-a", app, "--run-release-phase")

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Running release script")
      expect(result[:stderr]).to include("Failed to run release script")
      expect(result[:stderr]).not_to include("- rails:")
    end
  end

  context "when release script is valid" do
    let!(:app) { dummy_test_app("with-rails-with-non-app-image", create_if_not_exists: true) }

    before do
      ENV["APP_NAME"] = app

      allow(Kernel).to receive(:sleep)

      run_cpl_command!("ps:start", "-a", app, "--workload", "postgres", "--wait")
    end

    it "runs release script and deploys image", :slow do
      result = run_cpl_command("deploy-image", "-a", app, "--run-release-phase")

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Running release script")
      expect(result[:stderr]).not_to include("Failed to run release script")
      expect(result[:stderr]).to match(%r{- rails: https://rails-.+?.cpln.app})
      expect(result[:stderr]).not_to include("- rails-with-non-app-image:")
    end
  end
end
