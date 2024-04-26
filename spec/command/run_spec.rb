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

  context "when workload to clone exists" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    it "clones workload and runs bash by default", :slow do
      result = nil
      expected_regex = /Gemfile/

      spawn_cpl_command("run", "-a", app) do |it|
        it.wait_for_prompt
        it.type("ls")
        result = it.wait_for(expected_regex)
        it.type("exit")
      end

      expect(result).to match(expected_regex)
    end

    it "clones workload and runs provided command", :slow do
      result = nil
      expected_regex = /Gemfile/

      spawn_cpl_command("run", "-a", app, "--", "ls") do |it|
        result = it.wait_for(expected_regex)
      end

      expect(result).to match(expected_regex)
    end
  end

  context "when specifying image" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    it "clones workload and runs with latest image", :slow do
      result = nil
      expected_regex = %r{/org/.+?/image/#{app}:2}

      spawn_cpl_command("run", "-a", app, "--image", "latest") do |it|
        it.wait_for_prompt
        it.type("echo $CPLN_IMAGE")
        result = it.wait_for(expected_regex)
        it.type("exit")
      end

      expect(result).to match(expected_regex)
    end

    it "clones workload and runs with specific image", :slow do
      result = nil
      expected_regex = %r{/org/.+?/image/#{app}:1}

      spawn_cpl_command("run", "-a", app, "--image", "#{app}:1") do |it|
        it.wait_for_prompt
        it.type("echo $CPLN_IMAGE")
        result = it.wait_for(expected_regex)
        it.type("exit")
      end

      expect(result).to match(expected_regex)
    end
  end

  context "when specifying token" do
    let!(:token) { Shell.cmd("cpln", "profile", "token", "default")[:output].strip }
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    it "clones workload and runs with remote token", :slow do
      result = nil
      expected_regex = /REMOTE/

      spawn_cpl_command("run", "-a", app) do |it|
        it.wait_for_prompt
        it.type("if [ \"$CPLN_TOKEN\" = \"#{token}\" ]; then echo \"LOCAL\"; else echo \"REMOTE\"; fi")
        result = it.wait_for(expected_regex)
        it.type("exit")
      end

      expect(result).to match(expected_regex)
    end

    it "clones workload and runs with local token", :slow do
      result = nil
      expected_regex = /LOCAL/

      spawn_cpl_command("run", "-a", app, "--use-local-token") do |it|
        it.wait_for_prompt
        it.type("if [ \"$CPLN_TOKEN\" = \"#{token}\" ]; then echo \"LOCAL\"; else echo \"REMOTE\"; fi")
        result = it.wait_for(expected_regex)
        it.type("exit")
      end

      expect(result).to match(expected_regex)
    end
  end

  context "when 'fix_terminal_size' is provided" do
    let!(:app) { dummy_test_app("with-fix-terminal-size") }

    before do
      run_cpl_command!("apply-template", "gvc", "rails", "-a", app)
      run_cpl_command!("build-image", "-a", app)
      run_cpl_command!("deploy-image", "-a", app)
    end

    after do
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "clones workload and runs with fixed terminal size", :slow do
      result = nil
      expected_regex = /10 150/

      spawn_cpl_command("run", "-a", app, stty_rows: 10, stty_cols: 150) do |it|
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

      spawn_cpl_command("run", "-a", app, "--terminal-size", "20,300") do |it|
        it.wait_for_prompt
        it.type("stty size")
        result = it.wait_for(expected_regex)
        it.type("exit")
      end

      expect(result).to match(expected_regex)
    end

    it "clones workload and fails to run with provided terminal size due to invalid format", :slow do
      result = nil
      expected_regex = /0 0/

      spawn_cpl_command("run", "-a", app, "--terminal-size", "'20 300'") do |it|
        it.wait_for_prompt
        it.type("stty size")
        result = it.wait_for(expected_regex)
        it.type("exit")
      end

      expect(result).to match(expected_regex)
    end
  end
end
