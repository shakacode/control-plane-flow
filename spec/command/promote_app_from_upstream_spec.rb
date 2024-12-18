# frozen_string_literal: true

require "spec_helper"

describe Command::PromoteAppFromUpstream do
  subject(:result) do
    run_cpflow_command("promote-app-from-upstream", "-a", app, "--upstream-token", token, *extra_args)
  end

  let(:upstream_app) { dummy_test_app }
  let(:token) { Shell.cmd("cpln", "profile", "token", "default")[:output].strip }
  let(:extra_args) { [] }

  before do
    stub_env("CPLN_UPSTREAM", upstream_app)
    # Ideally, we should have a different org, but for testing purposes, this works
    stub_env("CPLN_ORG_UPSTREAM", dummy_test_org)
    stub_env("APP_NAME", app)

    run_cpflow_command!("apply-template", "app", "-a", upstream_app)
    run_cpflow_command!("apply-template", "app", "rails", "postgres", "-a", app)
    run_cpflow_command!("build-image", "-a", upstream_app)
  end

  after do
    run_cpflow_command!("delete", "-a", upstream_app, "--yes")
    run_cpflow_command!("delete", "-a", app, "--yes")
  end

  shared_examples "copies latest image from upstream and deploys image" do |**options|
    it "#{options[:runs_release_script] ? 'runs' : 'does not run'} release script", :slow do
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(%r{Pulling image from '.+?/#{upstream_app}:1'})
      expect(result[:stderr]).to match(%r{Pushing image to '.+?/#{app}:1'})

      if options[:runs_release_script]
        expect(result[:stderr]).to include("Running release script")
      else
        expect(result[:stderr]).not_to include("Running release script")
      end

      if options[:uses_digest_image_ref]
        expect(result[:stderr]).to match(/Deploying image '#{app}:1@sha256:[a-fA-F0-9]{64}'/)
      else
        expect(result[:stderr]).to match(/Deploying image '#{app}:1(?!@)'/)
      end

      expect(result[:stderr]).to match(%r{rails: https://rails-.+?.cpln.app})
    end
  end

  context "when release script is not provided" do
    let(:app) { dummy_test_app("nothing") }

    it_behaves_like "copies latest image from upstream and deploys image",
                    runs_release_script: false,
                    uses_digest_image_ref: false

    context "with use_digest_image_ref from YAML file" do
      let(:app) { dummy_test_app("use-digest-image-ref") }

      it_behaves_like "copies latest image from upstream and deploys image",
                      runs_release_script: false,
                      uses_digest_image_ref: true
    end

    context "with --use-digest-image-ref option" do
      let(:extra_args) { ["--use-digest-image-ref"] }

      it_behaves_like "copies latest image from upstream and deploys image",
                      runs_release_script: false,
                      uses_digest_image_ref: true
    end
  end

  context "when release script is invalid" do
    let(:app) { dummy_test_app("invalid-release-script") }

    before do
      run_cpflow_command!("ps:start", "-a", app, "--workload", "postgres", "--wait")
    end

    it "copies latest image from upstream, fails to run release script and fails to deploy image", :slow do
      result = run_cpflow_command("promote-app-from-upstream", "-a", app, "--upstream-token", token)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to match(%r{Pulling image from '.+?/#{upstream_app}:1'})
      expect(result[:stderr]).to match(%r{Pushing image to '.+?/#{app}:1'})
      expect(result[:stderr]).to include("Running release script")
      expect(result[:stderr]).to include("Failed to run release script")
      expect(result[:stderr]).not_to include("Deploying image")
      expect(result[:stderr]).not_to match(%r{rails: https://rails-.+?.cpln.app})
    end
  end

  context "when release script is valid" do
    let(:app) { dummy_test_app }

    before do
      run_cpflow_command!("ps:start", "-a", app, "--workload", "postgres", "--wait")
    end

    it_behaves_like "copies latest image from upstream and deploys image",
                    runs_release_script: true,
                    uses_digest_image_ref: false
  end
end
