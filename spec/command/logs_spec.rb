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
end
