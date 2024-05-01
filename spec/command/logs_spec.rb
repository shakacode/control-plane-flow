# frozen_string_literal: true

require "spec_helper"

describe Command::Logs do
  let!(:app) { dummy_test_app("full", create_if_not_exists: true) }
  let!(:message_regex) { /Fetching logs .+?\n/ }

  before do
    run_cpl_command!("ps:start", "-a", app, "--wait")
  end

  context "when no workload is provided" do
    it "displays logs for one-off workload", :slow do
      message_result = nil
      logs_result = nil
      logs_regex = /Rails .+? application starting in production/

      spawn_cpl_command("logs", "-a", app) do |it|
        message_result = it.wait_for(message_regex)
        logs_result = it.wait_for(logs_regex)
        it.kill
      end

      expect(message_result).to include("Fetching logs for workload 'rails'")
      expect(logs_result).to match(logs_regex)
    end
  end

  context "when workload is provided" do
    it "displays logs for specific workload", :slow do
      message_result = nil
      logs_result = nil
      logs_regex = /PostgreSQL init process complete/

      spawn_cpl_command("logs", "-a", app, "--workload", "postgres") do |it|
        message_result = it.wait_for(message_regex)
        logs_result = it.wait_for(logs_regex)
        it.kill
      end

      expect(message_result).to include("Fetching logs for workload 'postgres'")
      expect(logs_result).to match(logs_regex)
    end
  end

  context "when replica is provided" do
    let!(:replica) do
      run_cpl_command!("ps:stop", "-a", app, "--wait")
      run_cpl_command!("ps:start", "-a", app, "--wait")

      result = run_cpl_command!("ps", "-a", app, "--workload", "postgres")
      result[:stdout].strip
    end

    it "displays logs for specific replica", :slow do
      message_result = nil
      logs_result = nil
      logs_regex = /PostgreSQL init process complete/

      spawn_cpl_command("logs", "-a", app, "--workload", "postgres", "--replica", replica) do |it|
        message_result = it.wait_for(message_regex)
        logs_result = it.wait_for(logs_regex)
        it.kill
      end

      expect(message_result).to include("Fetching logs for replica '#{replica}'")
      expect(logs_result).to match(logs_regex)
    end
  end

  context "when using different limit on number of entries" do
    let!(:workload) do
      cmd = "'for i in {1..10}; do echo \"Line $i\"; done; while true; do sleep 1; done'"
      create_run_workload(cmd)
    end

    it "displays correct number of entries", :slow do
      result = nil
      expected_regex = /Line \d+/

      spawn_cpl_command("logs", "-a", app, "--workload", workload, "--limit", "5") do |it|
        result = it.wait_for(expected_regex)
        it.kill
      end

      expect(result).to include("Line 6")
    end
  end

  context "when using different loopback window" do
    let!(:workload) do
      cmd = "'echo \"Line 1\"; sleep 30; echo \"Line 2\"; while true; do sleep 1; done'"
      create_run_workload(cmd)
    end

    before do
      Kernel.sleep(30)
    end

    it "displays entries from correct duration", :slow do
      result = nil
      expected_regex = /Line \d+/

      spawn_cpl_command("logs", "-a", app, "--workload", workload, "--since", "30s") do |it|
        result = it.wait_for(expected_regex)
        it.kill
      end

      expect(result).to include("Line 2")
    end
  end

  def create_run_workload(cmd)
    runner_workload = nil

    runner_workload_regex = /runner workload '(.+?)'/
    spawn_cpl_command("run", "-a", app, "--", cmd, wait_for_process: false) do |it|
      runner_workload_result = it.wait_for(runner_workload_regex)
      runner_workload = runner_workload_result.match(runner_workload_regex)[1]

      it.wait_for(message_regex)
    end

    runner_workload
  end
end
