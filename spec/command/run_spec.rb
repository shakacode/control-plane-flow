# frozen_string_literal: true

require "spec_helper"

describe Command::Run do
  context "when workload to clone does not exist" do
    let!(:app) { dummy_test_app("default", create_if_not_exists: true) }

    it "raises error" do
      result = run_cpflow_command("run", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find workload 'rails'")
    end
  end

  context "when using interactive mode" do
    context "when workload to clone exists" do
      let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

      before do
        run_cpflow_command!("ps:start", "-a", app, "--workload", "postgres", "--wait")
      end

      it "clones workload and runs provided command", :slow do
        result = nil
        expected_regex = /Gemfile/

        spawn_cpflow_command("run", "-a", app, "--interactive", "--", "bash") do |it|
          it.wait_for_prompt
          it.type("ls")
          result = it.wait_for(expected_regex)
          it.type("exit")
        end

        expect(result).to match(expected_regex)
      end
    end

    context "when 'fix_terminal_size' is provided" do
      let!(:app) { dummy_test_app("fix-terminal-size") }

      before do
        run_cpflow_command!("apply-template", "app", "rails", "-a", app)
        run_cpflow_command!("build-image", "-a", app)
        run_cpflow_command!("deploy-image", "-a", app)
      end

      after do
        run_cpflow_command!("delete", "-a", app, "--yes")
      end

      it "clones workload and runs with fixed terminal size", :slow do
        result = nil
        expected_regex = /10 150/

        spawn_cpflow_command("run", "-a", app, "--entrypoint", "bash", stty_rows: 10, stty_cols: 150) do |it|
          it.wait_for_prompt
          it.type("stty size")
          result = it.wait_for(expected_regex)
          it.type("exit")
        end

        expect(result).to match(expected_regex)
      end
    end

    context "when terminal size is provided" do
      let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

      it "clones workload and runs with provided terminal size", :slow do
        result = nil
        expected_regex = /20 300/

        spawn_cpflow_command("run", "-a", app, "--entrypoint", "bash", "--terminal-size", "20,300") do |it|
          it.wait_for_prompt
          it.type("stty size")
          result = it.wait_for(expected_regex)
          it.type("exit")
        end

        expect(result).to match(expected_regex)
      end
    end
  end

  context "when using non-interactive mode" do
    context "when workload to clone exists" do
      let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

      it "clones workload and runs provided command with success", :slow do
        result = run_cpflow_command("run", "-a", app, "--entrypoint", "none", "--verbose", "--", "ls")

        expect(result[:status]).to eq(0)
        expect(result[:stderr]).not_to include("Updating runner workload")
        expect(result[:stderr]).to include("Gemfile")
        expect(result[:stderr]).to include("[JOB STATUS] successful")
      end

      it "clones workload and runs provided command with failure", :slow do
        result = run_cpflow_command("run", "-a", app, "--entrypoint", "none", "--verbose", "--", "nonexistent")

        expect(result[:status]).not_to eq(0)
        expect(result[:stderr]).not_to include("Gemfile")
        expect(result[:stderr]).to include("[JOB STATUS] failed")
      end

      it "waits for job to finish", :slow do
        result = run_cpflow_command("run", "-a", app, "--entrypoint", "none", "--verbose", "--", "sleep 10; ls")

        expect(result[:status]).to eq(0)
        expect(result[:stderr]).to include("Gemfile")
        expect(result[:stderr]).to include("[JOB STATUS] active")
        expect(result[:stderr]).to include("[JOB STATUS] successful")
      end
    end

    context "when not specifying image" do
      let!(:app) { dummy_test_app }
      let!(:cmd) { "echo $CPLN_IMAGE" }

      before do
        run_cpflow_command!("apply-template", "app", "rails", "-a", app)
        run_cpflow_command!("build-image", "-a", app)
        run_cpflow_command!("deploy-image", "-a", app)
        run_cpflow_command!("build-image", "-a", app)
      end

      after do
        run_cpflow_command!("delete", "-a", app, "--yes")
      end

      it "clones workload and runs with exact same image as original workload after running with latest image", :slow do
        result1 = run_cpflow_command("run", "-a", app, "--entrypoint", "none", "--image", "latest", "--", cmd)
        result2 = run_cpflow_command("run", "-a", app, "--entrypoint", "none", "--", cmd)

        expect(result1[:status]).to eq(0)
        expect(result2[:status]).to eq(0)
        expect(result1[:stderr]).to match(%r{/org/.+?/image/#{app}:2})
        expect(result2[:stderr]).to match(%r{/org/.+?/image/#{app}:1})
      end
    end

    context "when specifying image" do
      let!(:app) { dummy_test_app("full", create_if_not_exists: true) }
      let!(:cmd) { "echo $CPLN_IMAGE" }

      it "clones workload and runs with latest image", :slow do
        result = run_cpflow_command("run", "-a", app, "--entrypoint", "none", "--image", "latest", "--", cmd)

        expect(result[:status]).to eq(0)
        expect(result[:stderr]).to match(%r{/org/.+?/image/#{app}:2})
      end

      it "clones workload and runs with specific image", :slow do
        result = run_cpflow_command("run", "-a", app, "--entrypoint", "none", "--image", "#{app}:1", "--", cmd)

        expect(result[:status]).to eq(0)
        expect(result[:stderr]).to match(%r{/org/.+?/image/#{app}:1})
      end
    end

    context "when specifying token" do
      let!(:token) { Shell.cmd("cpln", "profile", "token", "default")[:output].strip }
      let!(:app) { dummy_test_app("full", create_if_not_exists: true) }
      let!(:cmd) { "if [ \"$CPLN_TOKEN\" = \"#{token}\" ]; then echo \"LOCAL\"; else echo \"REMOTE\"; fi" }

      it "clones workload and runs with remote token", :slow do
        result = run_cpflow_command("run", "-a", app, "--entrypoint", "none", "--", cmd)

        expect(result[:status]).to eq(0)
        expect(result[:stderr]).to include("REMOTE")
      end

      it "clones workload and runs with local token", :slow do
        result = run_cpflow_command("run", "-a", app, "--entrypoint", "none", "--use-local-token", "--", cmd)

        expect(result[:status]).to eq(0)
        expect(result[:stderr]).to include("LOCAL")
      end
    end

    context "when 'runner_job_timeout' is provided" do
      let!(:app) { dummy_test_app("runner-job-timeout") }

      before do
        run_cpflow_command!("apply-template", "app", "rails", "-a", app)
        run_cpflow_command!("build-image", "-a", app)
        run_cpflow_command!("deploy-image", "-a", app)
      end

      after do
        run_cpflow_command!("delete", "-a", app, "--yes")
      end

      it "clones workload and times out before finishing", :slow do
        result = run_cpflow_command("run", "-a", app, "--entrypoint", "none", "--", "sleep 100; ls")

        expect(result[:status]).not_to eq(0)
        expect(result[:stderr]).not_to include("Gemfile")
      end
    end

    context "when detatching" do
      let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

      it "prints commands to log and stop the job", :slow do
        result = run_cpflow_command("run", "-a", app, "--entrypoint", "none", "--detached", "--", "ls")

        expect(result[:status]).to eq(0)
        expect(result[:stderr]).to include("cpflow logs")
        expect(result[:stderr]).to include("cpflow ps:stop")
      end
    end

    context "when runner workload has non-default values" do
      let!(:app) { dummy_test_app("rails-env", create_if_not_exists: true) }

      before do
        run_cpflow_command!("apply-template", "rails-runner-with-non-default-values", "-a", app)
      end

      after do
        run_cpflow_command!("delete", "-a", app, "--workload", "rails-runner", "--yes")
      end

      it "updates runner workload", :slow do
        result = run_cpflow_command("run", "-a", app, "--entrypoint", "none", "--", "ls")

        expect(result[:status]).to eq(0)
        expect(result[:stderr]).to include("Updating runner workload")
        expect(result[:stderr]).to include("Gemfile")
      end
    end

    context "when runner workload has different ENV" do
      let!(:app) { dummy_test_app("rails-env", create_if_not_exists: true) }

      before do
        run_cpflow_command!("apply-template", "rails-runner-with-different-env", "-a", app)
      end

      after do
        run_cpflow_command!("delete", "-a", app, "--workload", "rails-runner", "--yes")
      end

      it "updates runner workload", :slow do
        result = run_cpflow_command("run", "-a", app, "--entrypoint", "none", "--", "ls")

        expect(result[:status]).to eq(0)
        expect(result[:stderr]).to include("Updating runner workload")
        expect(result[:stderr]).to include("Gemfile")
      end
    end
  end
end
