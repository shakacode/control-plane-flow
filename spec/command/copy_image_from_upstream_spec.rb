# frozen_string_literal: true

require "spec_helper"

describe Command::CopyImageFromUpstream do
  context "when Docker is not running" do
    let!(:app) { dummy_test_app }

    before do
      allow(Shell).to receive(:cmd).with("docker", "version", anything).and_return({ success: false })
    end

    it "raises error" do
      result = run_cpl_command("copy-image-from-upstream", "-a", app, "--upstream-token", "token")

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't run Docker")
    end
  end

  context "when 'upstream' is not defined" do
    let!(:app) { dummy_test_app("with-nothing") }

    it "raises error" do
      result = run_cpl_command("copy-image-from-upstream", "-a", app, "--upstream-token", "token")

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find option 'upstream'")
    end
  end

  context "when upstream app is not defined" do
    let!(:app) { dummy_test_app("with-undefined-upstream") }

    it "raises error" do
      result = run_cpl_command("copy-image-from-upstream", "-a", app, "--upstream-token", "token")

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find option 'cpln_org' for app 'undefined'")
    end
  end

  context "when 'cpln_org' is not defined for upstream app" do
    let!(:upstream_app) { dummy_test_app("without-org") }
    let!(:app) { dummy_test_app }

    before do
      ENV["CPLN_UPSTREAM"] = upstream_app
    end

    it "raises error" do
      result = run_cpl_command("copy-image-from-upstream", "-a", app, "--upstream-token", "token")

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find option 'cpln_org' for app '#{upstream_app}'")
    end
  end

  context "when using invalid token for upstream org" do
    let!(:upstream_app) { dummy_test_app }
    let!(:app) { dummy_test_app }

    before do
      ENV["CPLN_UPSTREAM"] = upstream_app
      # Ideally, we should have a different org, but for testing purposes, this works
      ENV["CPLN_ORG_UPSTREAM"] = dummy_test_org

      run_cpl_command!("apply-template", "gvc", "-a", upstream_app)
      run_cpl_command!("apply-template", "gvc", "-a", app)
    end

    after do
      run_cpl_command!("delete", "-a", upstream_app, "--yes")
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "fails to fetch upstream image URL", :slow do
      run_cpl_command!("build-image", "-a", upstream_app)
      result = run_cpl_command("copy-image-from-upstream", "-a", app, "--upstream-token", "token")

      expect(ENV.fetch("CPLN_PROFILE", nil)).to eq("default")
      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to match(/Creating upstream profile[.]+? done!/)
      expect(result[:stderr]).to match(/Fetching upstream image URL[.]+? failed!/)
      expect(result[:stderr]).to match(/Deleting upstream profile[.]+? done!/)
    end
  end

  context "when using valid token for upstream org" do
    let!(:token) { Shell.cmd("cpln", "profile", "token", "default")[:output].strip }
    let!(:upstream_app) { dummy_test_app }
    let!(:app) { dummy_test_app }

    before do
      ENV["CPLN_UPSTREAM"] = upstream_app
      # Ideally, we should have a different org, but for testing purposes, this works
      ENV["CPLN_ORG_UPSTREAM"] = dummy_test_org

      run_cpl_command!("apply-template", "gvc", "-a", upstream_app)
      run_cpl_command!("apply-template", "gvc", "-a", app)
    end

    after do
      run_cpl_command!("delete", "-a", upstream_app, "--yes")
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "copies images from upstream", :slow do
      # Simulates looping through generated profile names to avoid conflicts
      allow_any_instance_of(Controlplane).to receive(:profile_exists?).and_return(true, false) # rubocop:disable RSpec/AnyInstance

      run_cpl_command!("build-image", "-a", upstream_app, "--commit", "abc123")
      run_cpl_command!("build-image", "-a", upstream_app)
      # Copies latest image
      result1 = run_cpl_command("copy-image-from-upstream", "-a", app, "--upstream-token", token)
      # Copies specific image with commit hash
      result2 = run_cpl_command("copy-image-from-upstream", "-a", app, "--upstream-token", token,
                                "--image", "#{upstream_app}:1_abc123")

      expect(ENV.fetch("CPLN_PROFILE", nil)).to eq("default")
      expect(result1[:status]).to eq(0)
      expect(result2[:status]).to eq(0)
      expect(result1[:stderr]).to match(/Creating upstream profile[.]+? done!/)
      expect(result1[:stderr]).to match(/Fetching upstream image URL[.]+? done!/)
      expect(result1[:stderr]).to match(/Fetching app image URL[.]+? done!/)
      expect(result1[:stderr]).to match(%r{Pulling image from '.+?/#{upstream_app}:2'[.]+? done!})
      expect(result1[:stderr]).to match(%r{Pushing image to '.+?/#{app}:1'[.]+? done!})
      expect(result1[:stderr]).to match(/Deleting upstream profile[.]+? done!/)
      expect(result2[:stderr]).to match(/Creating upstream profile[.]+? done!/)
      expect(result2[:stderr]).to match(/Fetching upstream image URL[.]+? done!/)
      expect(result2[:stderr]).to match(/Fetching app image URL[.]+? done!/)
      expect(result2[:stderr]).to match(%r{Pulling image from '.+?/#{upstream_app}:1_abc123'[.]+? done!})
      expect(result2[:stderr]).to match(%r{Pushing image to '.+?/#{app}:2_abc123'[.]+? done!})
      expect(result2[:stderr]).to match(/Deleting upstream profile[.]+? done!/)
    end
  end
end
