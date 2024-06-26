# frozen_string_literal: true

require "spec_helper"

describe Command::BuildImage do
  context "when Docker is not running" do
    let!(:app) { dummy_test_app }

    before do
      allow(Shell).to receive(:cmd).with("docker", "version", anything).and_return({ success: false })
    end

    it "raises error" do
      result = run_cpflow_command("build-image", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't run Docker")
    end
  end

  context "when Dockerfile does not exist" do
    let!(:app) { dummy_test_app("nonexistent-dockerfile") }

    it "raises error" do
      result = run_cpflow_command("build-image", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find Dockerfile")
    end
  end

  context "when Dockerfile is invalid" do
    let!(:app) { dummy_test_app("invalid-dockerfile") }

    it "fails to build and push image" do
      result = run_cpflow_command("build-image", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).not_to include("Pushed image")
    end
  end

  context "when Dockerfile is valid" do
    let!(:app) { dummy_test_app }

    before do
      run_cpflow_command!("apply-template", "app", "-a", app)
    end

    after do
      run_cpflow_command!("delete", "-a", app, "--yes")
    end

    it "builds and pushes images", :slow do
      result1 = run_cpflow_command("build-image", "-a", app)
      # Subsequent build increases number
      result2 = run_cpflow_command("build-image", "-a", app)
      # Adds commit hash
      result3 = run_cpflow_command("build-image", "-a", app, "--commit", "abc123")

      expect(result1[:status]).to eq(0)
      expect(result2[:status]).to eq(0)
      expect(result3[:status]).to eq(0)
      expect(result1[:stderr]).to match(%r{Pushed image to '/org/.+?/image/#{app}:1'})
      expect(result2[:stderr]).to match(%r{Pushed image to '/org/.+?/image/#{app}:2'})
      expect(result3[:stderr]).to match(%r{Pushed image to '/org/.+?/image/#{app}:3_abc123'})
    end

    it "passes additional options to `docker build`", :slow do
      allow(Process).to receive(:spawn).with(match(/docker build.+?TEST=123/)).and_call_original
      allow(Process).to receive(:spawn).with(include("docker push")).and_call_original

      result = run_cpflow_command("build-image", "-a", app, "--build-arg", "TEST=123")

      expect(Process).to have_received(:spawn).twice
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(%r{Pushed image to '/org/.+?/image/#{app}:1'})
    end
  end
end
