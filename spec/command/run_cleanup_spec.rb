# frozen_string_literal: true

require "spec_helper"

describe Command::RunCleanup do
  context "when 'stale_run_workload_created_days' is not defined" do
    let!(:app) { dummy_test_app("with-nothing") }

    it "raises error" do
      result = run_cpl_command("run:cleanup", "-a", app)

      expect(result[:status]).to eq(1)
      expect(result[:stderr]).to include("Can't find option 'stale_run_workload_created_days'")
    end
  end

  context "when there are no stale run workloads to delete" do
    let!(:app) { dummy_test_app }

    it "displays message" do
      result = run_cpl_command("run:cleanup", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("No stale run workloads found")
    end
  end

  context "when run workload matches defined workload exactly" do
    let!(:app) { dummy_test_app("with-fake-run-workload") }

    before do
      run_cpl_command!("apply-template", "gvc", "fake-run-12345", "-a", app)
    end

    after do
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "lists nothing" do
      travel_to_days_later(3)
      result = run_cpl_command("run:cleanup", "-a", app)
      travel_back

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("No stale run workloads found")
    end
  end

  context "when run workloads do not match naming pattern exactly" do
    let!(:app) { dummy_test_app }

    before do
      run_cpl_command!("apply-template", "gvc", "fake-run-12345", "fake-runner-12345", "-a", app)
    end

    after do
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "lists nothing" do
      travel_to_days_later(3)
      result = run_cpl_command("run:cleanup", "-a", app)
      travel_back

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("No stale run workloads found")
    end
  end

  context "when run workloads are not older than 'stale_run_workload_created_days'" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    before do
      create_run_workloads(app)
    end

    it "lists nothing", :slow do
      result = run_cpl_command("run:cleanup", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("No stale run workloads found")
    end
  end

  context "when there are stale run workloads to delete" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    before do
      create_run_workloads(app)
    end

    it "asks for confirmation and does nothing", :slow do
      allow(Shell).to receive(:confirm).with(match(/\d+ run workloads/)).and_return(false)

      travel_to_days_later(3)
      result = run_cpl_command("run:cleanup", "-a", app)
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).not_to include("Deleting run workload")
    end

    it "asks for confirmation and deletes stale run workloads", :slow do
      allow(Shell).to receive(:confirm).with(match(/\d+ run workloads/)).and_return(true)

      travel_to_days_later(3)
      result = run_cpl_command("run:cleanup", "-a", app)
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Deleting run workload '#{app}: rails-run-\d{4}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting run workload '#{app}: rails-runner-\d{4}'[.]+? done!/)
    end

    it "skips confirmation and deletes stale run workloads", :slow do
      allow(Shell).to receive(:confirm).and_return(false)

      travel_to_days_later(3)
      result = run_cpl_command("run:cleanup", "-a", app, "--yes")
      travel_back

      expect(Shell).not_to have_received(:confirm)
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Deleting run workload '#{app}: rails-run-\d{4}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting run workload '#{app}: rails-runner-\d{4}'[.]+? done!/)
    end
  end

  context "with multiple apps" do
    let!(:app_prefix) { dummy_test_app_prefix("full") }
    let!(:app1) { dummy_test_app("full", "1", create_if_not_exists: true) }
    let!(:app2) { dummy_test_app("full", "2", create_if_not_exists: true) }

    before do
      create_run_workloads(app1)
      create_run_workloads(app2)
    end

    it "lists correct run workloads from exact app", :slow do
      allow(Shell).to receive(:confirm).with(match(/\d+ run workloads/)).and_return(false)

      travel_to_days_later(3)
      result = run_cpl_command("run:cleanup", "-a", app1)
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/- #{app1}: rails-run-\d{4}/)
      expect(result[:stderr]).to match(/- #{app1}: rails-runner-\d{4}/)
    end

    it "lists correct run workloads from all matching apps", :slow do
      allow(Shell).to receive(:confirm).with(match(/\d+ run workloads/)).and_return(false)

      travel_to_days_later(3)
      result = run_cpl_command("run:cleanup", "-a", app_prefix)
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/- #{app1}: rails-run-\d{4}/)
      expect(result[:stderr]).to match(/- #{app1}: rails-runner-\d{4}/)
      expect(result[:stderr]).to match(/- #{app2}: rails-run-\d{4}/)
      expect(result[:stderr]).to match(/- #{app2}: rails-runner-\d{4}/)
    end
  end

  def create_run_workloads(app)
    spawn_cpl_command("run", "-a", app, wait_for_process: false, &:wait_for_prompt)

    cmd = "\"bash -c 'while true; do sleep 1; done'\""
    expected_regex = /STARTED RUNNER SCRIPT/
    spawn_cpl_command("run:detached", "-a", app, "--", cmd, wait_for_process: false) do |it|
      it.wait_for(expected_regex)
    end
  end
end
