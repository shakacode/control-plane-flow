# frozen_string_literal: true

require "spec_helper"

describe Command::Logs do
  let!(:app) { dummy_test_app("full", create_if_not_exists: true) }
  let!(:message_regex) { /Fetching logs .+?\n/ }

  before do
    run_cpflow_command!("ps:start", "-a", app, "--wait")
  end

  context "when no workload is provided" do
    it "displays logs for one-off workload", :slow do
      message_result = nil
      logs_result = nil
      logs_regex = /Rails .+? application starting in production/

      spawn_cpflow_command("logs", "-a", app) do |it|
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

      spawn_cpflow_command("logs", "-a", app, "--workload", "postgres") do |it|
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
      run_cpflow_command!("ps:stop", "-a", app, "--wait")
      run_cpflow_command!("ps:start", "-a", app, "--wait")

      result = run_cpflow_command!("ps", "-a", app, "--workload", "postgres")
      result[:stdout].strip
    end

    it "displays logs for specific replica", :slow do
      message_result = nil
      logs_result = nil
      logs_regex = /PostgreSQL init process complete/

      spawn_cpflow_command("logs", "-a", app, "--workload", "postgres", "--replica", replica) do |it|
        message_result = it.wait_for(message_regex)
        logs_result = it.wait_for(logs_regex)
        it.kill
      end

      expect(message_result).to include("Fetching logs for replica '#{replica}'")
      expect(logs_result).to match(logs_regex)
    end
  end

  context "when using different limit on number of entries" do
    let!(:cmd_args) do
      cmd = 'for i in {0..9}; do echo "Line $i"; done; while true; do sleep 1; done'
      create_run_workload(cmd)
    end

    before do
      Kernel.sleep(30)
    end

    after do
      run_cpflow_command!(*cmd_args[:ps_stop])
    end

    it "displays correct number of entries", :slow do
      result = nil

      spawn_cpflow_command(*cmd_args[:logs], "--limit", "5") do |it|
        result = it.wait_for(/Line 9/)
        it.kill
      end

      expect(result).not_to match(/Line [0-4]/)
      expect(result).to match(/Line [5-9]/)
    end
  end

  context "when using different loopback window" do
    let!(:cmd_args) do
      cmd = 'echo "Line 1"; sleep 30; while true; do echo "Line 2"; sleep 1; done'
      create_run_workload(cmd)
    end

    before do
      Kernel.sleep(30)
    end

    after do
      run_cpflow_command!(*cmd_args[:ps_stop])
    end

    it "displays entries from correct duration", :slow do
      result = nil

      spawn_cpflow_command(*cmd_args[:logs], "--since", "30s") do |it|
        result = it.wait_for(/Line 2/)
        it.kill
      end

      expect(result).not_to include("Line 1")
      expect(result).to include("Line 2")
    end
  end

  def create_run_workload(cmd)
    result = run_cpflow_command("run", "-a", app, "--detached", "--", cmd)

    {
      logs: result[:stderr].match(/`cpflow (logs .+?)`/)[1].split,
      ps_stop: result[:stderr].match(/`cpflow (ps:stop .+?)`/)[1].split
    }
  end
end
