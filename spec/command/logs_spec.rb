# frozen_string_literal: true

require "spec_helper"

describe Command::Logs do
  let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

  before do
    run_cpl_command!("ps:start", "-a", app, "--wait")
  end

  context "when no workload is provided" do
    it "displays logs for one-off workload", :slow do
      result = nil
      expected_regex = /Rails .+? application starting in production/

      spawn_cpl_command("logs", "-a", app) do |it|
        result = it.wait_for(expected_regex)
        it.kill
      end

      expect(result).to match(expected_regex)
    end
  end

  context "when workload is provided" do
    it "displays logs for specific workload", :slow do
      result = nil
      expected_regex = /PostgreSQL init process complete/

      spawn_cpl_command("logs", "-a", app, "--workload", "postgres") do |it|
        result = it.wait_for(expected_regex)
        it.kill
      end

      expect(result).to match(expected_regex)
    end
  end

  context "when using different limit on number of entries" do
    let!(:workload) do
      cmd = "\"bash -c 'for i in {1..10}; do echo \\\"Line \\\\\\$i\\\"; done; while true; do sleep 1; done'\""
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
      cmd = "\"bash -c 'echo \\\"Line 1\\\"; sleep 30; echo \\\"Line 2\\\"; while true; do sleep 1; done'\""
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
    workload_clone = nil

    cloning_regex = /Cloning workload '.+?' on app '.+?' to '(.+?)'/
    started_regex = /STARTED RUNNER SCRIPT/
    spawn_cpl_command("run:detached", "-a", app, "--", cmd, wait_for_process: false) do |it|
      cloning_result = it.wait_for(cloning_regex)
      workload_clone = cloning_result.match(cloning_regex)[1]

      it.wait_for(started_regex)
    end

    workload_clone
  end
end
