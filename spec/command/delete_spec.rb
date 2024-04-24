# frozen_string_literal: true

require "spec_helper"

describe Command::Delete do
  context "when app does not exist" do
    let!(:app) { dummy_test_app }

    it "displays message" do
      result = run_cpl_command("delete", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("App '#{app}' does not exist")
    end
  end

  context "when app exists" do
    let!(:app) { dummy_test_app }

    before do
      run_cpl_command!("apply-template", "gvc", "-a", app)
    end

    after do
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "asks for confirmation and does nothing" do
      allow(Shell).to receive(:confirm).with(include(app)).and_return(false)

      result = run_cpl_command("delete", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("No volumesets to delete")
      expect(result[:stderr]).to include("No images to delete")
      expect(result[:stderr]).not_to include("Deleting app")
    end

    it "asks for confirmation and deletes app" do
      allow(Shell).to receive(:confirm).with(include(app)).and_return(true)

      result = run_cpl_command("delete", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("No volumesets to delete")
      expect(result[:stderr]).to include("No images to delete")
      expect(result[:stderr]).to match(/Deleting app '#{app}'[.]+? done!/)
    end

    it "skips confirmation and deletes app" do
      allow(Shell).to receive(:confirm).and_return(false)

      result = run_cpl_command("delete", "-a", app, "--yes")

      expect(Shell).not_to have_received(:confirm)
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("No volumesets to delete")
      expect(result[:stderr]).to include("No images to delete")
      expect(result[:stderr]).to match(/Deleting app '#{app}'[.]+? done!/)
    end
  end

  context "when app has volumesets and images" do
    let!(:app) { dummy_test_app }

    before do
      run_cpl_command!("apply-template", "gvc", "rails", "redis-with-volume", "detached-volume", "-a", app)
      run_cpl_command!("build-image", "-a", app)
    end

    after do
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "deletes app with volumesets and images", :slow do
      allow(Shell).to receive(:confirm).with(include(app)).and_return(true)

      result = run_cpl_command("delete", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Deleting volumeset 'detached-volume'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting volumeset 'redis-volume'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting app '#{app}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting image '#{app}:1'[.]+? done!/)
    end
  end
end
