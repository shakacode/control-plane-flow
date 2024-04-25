# frozen_string_literal: true

require "spec_helper"

describe Command::RunDetached do
  context "when workload to clone does not exist" do
    let!(:app) { dummy_test_app("default", create_if_not_exists: true) }

    it "raises error" do
      result = run_cpl_command("run:detached", "-a", app, "--", "ls")

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find workload 'rails'")
    end
  end

  context "when workload to clone exists" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    it "keeps retrying until MAX_RETRIES if runtime error happens", :slow do
      stub_const("Command::RunDetached::MAX_RETRIES", 3)
      allow_any_instance_of(described_class).to receive(:print_uniq_logs).and_raise(RuntimeError, "Runtime error.") # rubocop:disable RSpec/AnyInstance

      result = run_cpl_command("run:detached", "-a", app, "--", "ls")

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Retrying").exactly(3).times
      expect(result[:stderr]).to include("Exiting")
    end

    it "deletes workload if finished with success", :slow do
      result = run_cpl_command("run:detached", "-a", app, "--", "ls")

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Gemfile")
      expect(result[:stderr]).to include("DELETING WORKLOAD")
    end

    it "deletes workload if finished with failure by default", :slow do
      result = run_cpl_command("run:detached", "-a", app, "--", "unexistent")

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("CRASHED")
      expect(result[:stderr]).to include("DELETING WORKLOAD")
    end

    it "does not delete workload if finished with failure and --no-clean-on-failure is provided", :slow do
      result = run_cpl_command("run:detached", "-a", app, "--no-clean-on-failure", "--", "unexistent")

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("CRASHED")
      expect(result[:stderr]).not_to include("DELETING WORKLOAD")
    end
  end

  context "when specifying image" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    it "clones workload and runs with latest image", :slow do
      result = run_cpl_command("run:detached", "-a", app, "--image", "latest", "--", "echo $CPLN_IMAGE")

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(%r{/org/.+?/image/#{app}:2})
    end

    it "clones workload and runs with specific image", :slow do
      result = run_cpl_command("run:detached", "-a", app, "--image", "#{app}:1", "--", "echo $CPLN_IMAGE")

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(%r{/org/.+?/image/#{app}:1})
    end
  end

  context "when specifying token" do
    let!(:token) { Shell.cmd("cpln profile token default")[:output].strip }
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    it "clones workload and runs with remote token", :slow do
      cmd = "bash -c 'if [ \"$CPLN_TOKEN\" = \"#{token}\" ]; then echo \"LOCAL\"; else echo \"REMOTE\"; fi'"
      result = run_cpl_command("run:detached", "-a", app, "--", cmd)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("REMOTE")
    end

    it "clones workload and runs with local token", :slow do
      cmd = "bash -c 'if [ \"$CPLN_TOKEN\" = \"#{token}\" ]; then echo \"LOCAL\"; else echo \"REMOTE\"; fi'"
      result = run_cpl_command("run:detached", "-a", app, "--use-local-token", "--", cmd)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("LOCAL")
    end
  end
end
