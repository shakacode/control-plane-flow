# frozen_string_literal: true

require "spec_helper"

describe Command::PromoteAppFromUpstream do
  context "when release script is not provided" do
    let!(:token) { Shell.cmd("cpln profile token default")[:output].strip }
    let!(:upstream_app) { dummy_test_app }
    let!(:app) { dummy_test_app("with-nothing") }

    before do
      ENV["CPLN_UPSTREAM"] = upstream_app
      # Ideally, we should have a different org, but for testing purposes, this works
      ENV["CPLN_ORG_UPSTREAM"] = dummy_test_org

      run_cpl_command!("apply-template", "gvc", "-a", upstream_app)
      run_cpl_command!("apply-template", "gvc", "rails", "-a", app)
      run_cpl_command!("build-image", "-a", upstream_app)
    end

    after do
      run_cpl_command!("delete", "-a", upstream_app, "--yes")
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "copies latest image from upstream, skips release script and deploys image", :slow do
      result = run_cpl_command("promote-app-from-upstream", "-a", app, "--upstream-token", token)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(%r{Pulling image from '.+?/#{upstream_app}:1'})
      expect(result[:stderr]).to match(%r{Pushing image to '.+?/#{app}:1'})
      expect(result[:stderr]).not_to include("Running release script")
      expect(result[:stderr]).to match(%r{rails: https://rails-.+?.cpln.app})
    end
  end

  context "when release script is invalid" do
    let!(:token) { Shell.cmd("cpln profile token default")[:output].strip }
    let!(:upstream_app) { dummy_test_app }
    let!(:app) { dummy_test_app("with-invalid-release-script") }

    before do
      ENV["CPLN_UPSTREAM"] = upstream_app
      # Ideally, we should have a different org, but for testing purposes, this works
      ENV["CPLN_ORG_UPSTREAM"] = dummy_test_org
      ENV["APP_NAME"] = app

      run_cpl_command!("apply-template", "gvc", "-a", upstream_app)
      run_cpl_command!("apply-template", "gvc", "rails", "-a", app)
      run_cpl_command!("build-image", "-a", upstream_app)
    end

    after do
      run_cpl_command!("delete", "-a", upstream_app, "--yes")
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "copies latest image from upstream, fails to run release script and fails to deploy image", :slow do
      result = run_cpl_command("promote-app-from-upstream", "-a", app, "--upstream-token", token)

      expect(result[:status]).to eq(1)
      expect(result[:stderr]).to match(%r{Pulling image from '.+?/#{upstream_app}:1'})
      expect(result[:stderr]).to match(%r{Pushing image to '.+?/#{app}:1'})
      expect(result[:stderr]).to include("Running release script")
      expect(result[:stderr]).to include("Failed to run release script")
      expect(result[:stderr]).not_to match(%r{rails: https://rails-.+?.cpln.app})
    end
  end

  context "when release script is valid" do
    let!(:token) { Shell.cmd("cpln profile token default")[:output].strip }
    let!(:upstream_app) { dummy_test_app }
    let!(:app) { dummy_test_app }

    before do
      ENV["CPLN_UPSTREAM"] = upstream_app
      # Ideally, we should have a different org, but for testing purposes, this works
      ENV["CPLN_ORG_UPSTREAM"] = dummy_test_org
      ENV["APP_NAME"] = app

      run_cpl_command!("apply-template", "gvc", "-a", upstream_app)
      run_cpl_command!("apply-template", "gvc", "rails", "postgres", "-a", app)
      run_cpl_command!("build-image", "-a", upstream_app)
      run_cpl_command!("ps:start", "-a", app, "--workload", "postgres", "--wait")
    end

    after do
      run_cpl_command!("delete", "-a", upstream_app, "--yes")
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "copies latest image from upstream, runs release script and deploys image", :slow do
      result = run_cpl_command("promote-app-from-upstream", "-a", app, "--upstream-token", token)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(%r{Pulling image from '.+?/#{upstream_app}:1'})
      expect(result[:stderr]).to match(%r{Pushing image to '.+?/#{app}:1'})
      expect(result[:stderr]).to include("Running release script")
      expect(result[:stderr]).not_to include("Failed to run release script")
      expect(result[:stderr]).to match(%r{rails: https://rails-.+?.cpln.app})
    end
  end
end
