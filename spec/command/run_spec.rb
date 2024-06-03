# frozen_string_literal: true

require "spec_helper"

describe Command::Run do
  context "when workload to clone does not exist" do
    let!(:app) { dummy_test_app("default", create_if_not_exists: true) }

    it "raises error" do
      result = run_cpl_command("run", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find workload 'rails'")
    end
  end

  context "when using interactive mode" do
    context "when workload to clone exists" do
      let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

      before do
        run_cpl_command!("ps:start", "-a", app, "--workload", "postgres", "--wait")
      end

      it "clones workload and runs provided command", :slow do
        result = nil
        expected_regex = /Gemfile/

        spawn_cpl_command("run", "-a", app, "--interactive", "--", "bash") do |it|
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
        run_cpl_command!("apply-template", "app", "rails", "-a", app)
        run_cpl_command!("build-image", "-a", app)
        run_cpl_command!("deploy-image", "-a", app)
      end

      after do
        run_cpl_command!("delete", "-a", app, "--yes")
      end

      it "clones workload and runs with fixed terminal size", :slow do
        result = nil
        expected_regex = /10 150/

        spawn_cpl_command("run", "-a", app, "--entrypoint", "bash", stty_rows: 10, stty_cols: 150) do |it|
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

        spawn_cpl_command("run", "-a", app, "--entrypoint", "bash", "--terminal-size", "20,300") do |it|
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
        result = nil

        spawn_cpl_command("run", "-a", app, "--entrypoint", "none", "--verbose", "--", "ls") do |it|
          result = it.read_full_output
        end

        expect(result).to include("Gemfile")
        expect(result).to include("[#{Shell.color('JOB STATUS', :red)}] successful")
      end

      it "clones workload and runs provided command with failure", :slow do
        result = nil

        spawn_cpl_command("run", "-a", app, "--entrypoint", "none", "--verbose", "--", "nonexistent") do |it|
          result = it.read_full_output
        end

        expect(result).not_to include("Gemfile")
        expect(result).to include("[#{Shell.color('JOB STATUS', :red)}] failed")
      end

      it "waits for job to finish", :slow do
        result = nil

        spawn_cpl_command("run", "-a", app, "--entrypoint", "none", "--verbose", "--", "'sleep 10; ls'") do |it|
          result = it.read_full_output
        end

        expect(result).to include("Gemfile")
        expect(result).to include("[#{Shell.color('JOB STATUS', :red)}] active")
        expect(result).to include("[#{Shell.color('JOB STATUS', :red)}] successful")
      end
    end

    context "when not specifying image" do
      let!(:app) { dummy_test_app }
      let!(:cmd) { "'echo $CPLN_IMAGE'" }

      before do
        run_cpl_command!("apply-template", "app", "rails", "-a", app)
        run_cpl_command!("build-image", "-a", app)
        run_cpl_command!("deploy-image", "-a", app)
        run_cpl_command!("build-image", "-a", app)
      end

      after do
        run_cpl_command!("delete", "-a", app, "--yes")
      end

      it "clones workload and runs with exact same image as original workload after running with latest image", :slow do
        result1 = nil
        result2 = nil

        spawn_cpl_command("run", "-a", app, "--entrypoint", "none", "--image", "latest", "--", cmd) do |it|
          result1 = it.read_full_output
        end
        spawn_cpl_command("run", "-a", app, "--entrypoint", "none", "--", cmd) do |it|
          result2 = it.read_full_output
        end

        expect(result1).to match(%r{/org/.+?/image/#{app}:2})
        expect(result2).to match(%r{/org/.+?/image/#{app}:1})
      end
    end

    context "when specifying image" do
      let!(:app) { dummy_test_app("full", create_if_not_exists: true) }
      let!(:cmd) { "'echo $CPLN_IMAGE'" }

      it "clones workload and runs with latest image", :slow do
        result = nil

        spawn_cpl_command("run", "-a", app, "--entrypoint", "none", "--image", "latest", "--", cmd) do |it|
          result = it.read_full_output
        end

        expect(result).to match(%r{/org/.+?/image/#{app}:2})
      end

      it "clones workload and runs with specific image", :slow do
        result = nil

        spawn_cpl_command("run", "-a", app, "--entrypoint", "none", "--image", "#{app}:1", "--", cmd) do |it|
          result = it.read_full_output
        end

        expect(result).to match(%r{/org/.+?/image/#{app}:1})
      end
    end

    context "when specifying token" do
      let!(:token) { Shell.cmd("cpln", "profile", "token", "default")[:output].strip }
      let!(:app) { dummy_test_app("full", create_if_not_exists: true) }
      let!(:cmd) { "'if [ \"$CPLN_TOKEN\" = \"#{token}\" ]; then echo \"LOCAL\"; else echo \"REMOTE\"; fi'" }

      it "clones workload and runs with remote token", :slow do
        result = nil

        spawn_cpl_command("run", "-a", app, "--entrypoint", "none", "--", cmd) do |it|
          result = it.read_full_output
        end

        expect(result).to include("REMOTE")
      end

      it "clones workload and runs with local token", :slow do
        result = nil

        spawn_cpl_command("run", "-a", app, "--entrypoint", "none", "--use-local-token", "--", cmd) do |it|
          result = it.read_full_output
        end

        expect(result).to include("LOCAL")
      end
    end

    context "when 'runner_job_timeout' is provided" do
      let!(:app) { dummy_test_app("runner-job-timeout") }

      before do
        run_cpl_command!("apply-template", "app", "rails", "-a", app)
        run_cpl_command!("build-image", "-a", app)
        run_cpl_command!("deploy-image", "-a", app)
      end

      after do
        run_cpl_command!("delete", "-a", app, "--yes")
      end

      it "clones workload and times out before finishing", :slow do
        result = nil

        spawn_cpl_command("run", "-a", app, "--entrypoint", "none", "--", "'sleep 100; ls'") do |it|
          result = it.read_full_output
        end

        expect(result).not_to include("Gemfile")
      end
    end

    context "when detatching" do
      let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

      it "prints commands to log and stop the job", :slow do
        result = nil

        spawn_cpl_command("run", "-a", app, "--entrypoint", "none", "--detached", "--", "ls") do |it|
          result = it.read_full_output
        end

        expect(result).to include("cpl logs")
        expect(result).to include("cpl ps:stop")
      end
    end
  end
end
