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
      run_cpl_command!("apply-template", "app", "-a", app)
    end

    after do
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "asks for confirmation and does nothing" do
      allow(Shell).to receive(:confirm).with(include(app)).and_return(false)

      result = run_cpl_command("delete", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("No volumesets to delete from app '#{app}'")
      expect(result[:stderr]).to include("No images to delete from app '#{app}'")
      expect(result[:stderr]).not_to include("Deleting app")
    end

    it "asks for confirmation and deletes app" do
      allow(Shell).to receive(:confirm).with(include(app)).and_return(true)

      result = run_cpl_command("delete", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("No volumesets to delete from app '#{app}'")
      expect(result[:stderr]).to include("No images to delete from app '#{app}'")
      expect(result[:stderr]).to match(/Deleting app '#{app}'[.]+? done!/)
    end

    it "skips confirmation and deletes app" do
      allow(Shell).to receive(:confirm).and_return(false)

      result = run_cpl_command("delete", "-a", app, "--yes")

      expect(Shell).not_to have_received(:confirm)
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("No volumesets to delete from app '#{app}'")
      expect(result[:stderr]).to include("No images to delete from app '#{app}'")
      expect(result[:stderr]).to match(/Deleting app '#{app}'[.]+? done!/)
    end
  end

  context "when app has volumesets and images" do
    let!(:app) { dummy_test_app }

    before do
      run_cpl_command!("apply-template", "app", "rails", "postgres-with-volume", "detached-volume", "-a", app)
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
      expect(result[:stderr]).to match(/Deleting volumeset 'detached-volume' from app '#{app}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting volumeset 'postgres-volume' from app '#{app}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting app '#{app}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting image '#{app}:1' from app '#{app}'[.]+? done!/)
    end
  end

  context "when workload does not exist" do
    let!(:app) { dummy_test_app }

    before do
      run_cpl_command!("apply-template", "app", "-a", app)
    end

    after do
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "displays message" do
      result = run_cpl_command("delete", "-a", app, "--workload", "rails")

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Workload 'rails' does not exist in app '#{app}'")
    end
  end

  context "when workload exists" do
    let!(:app) { dummy_test_app }

    before do
      run_cpl_command!("apply-template", "app", "rails", "-a", app)
    end

    after do
      run_cpl_command!("delete", "-a", app, "--yes")
    end

    it "asks for confirmation and does nothing" do
      allow(Shell).to receive(:confirm).with(include("rails")).and_return(false)

      result = run_cpl_command("delete", "-a", app, "--workload", "rails")

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).not_to include("Deleting workload")
    end

    it "asks for confirmation and deletes workload" do
      allow(Shell).to receive(:confirm).with(include("rails")).and_return(true)

      result = run_cpl_command("delete", "-a", app, "--workload", "rails")

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Deleting workload 'rails' from app '#{app}'[.]+? done!/)
    end

    it "skips confirmation and deletes workload" do
      allow(Shell).to receive(:confirm).and_return(false)

      result = run_cpl_command("delete", "-a", app, "--workload", "rails", "--yes")

      expect(Shell).not_to have_received(:confirm)
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Deleting workload 'rails' from app '#{app}'[.]+? done!/)
    end
  end

  context "when identity does not exist" do
    let!(:app) { dummy_test_app("nonexistent-identity") }

    before do
      run_cpl_command!("setup-app", "-a", app, "--skip-secret-access-binding")
    end

    it "does not unbind identity from policy" do
      allow(Shell).to receive(:confirm).with(include(app)).and_return(true)

      result = run_cpl_command("delete", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Deleting app '#{app}'[.]+? done!/)
      expect(result[:stderr]).not_to include("Unbinding identity from policy")
    end
  end

  context "when policy does not exist" do
    let!(:app) { dummy_test_app("nonexistent-policy") }

    before do
      run_cpl_command!("setup-app", "-a", app, "--skip-secret-access-binding")
    end

    it "does not unbind identity from policy" do
      allow(Shell).to receive(:confirm).with(include(app)).and_return(true)

      result = run_cpl_command("delete", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Deleting app '#{app}'[.]+? done!/)
      expect(result[:stderr]).not_to include("Unbinding identity from policy")
    end
  end

  context "when identity and policy are not bound" do
    let!(:app) { dummy_test_app("secrets") }

    before do
      run_cpl_command!("apply-template", "secrets", "-a", app)
      run_cpl_command!("setup-app", "-a", app, "--skip-secret-access-binding")
    end

    it "does not unbind identity from policy" do
      allow(Shell).to receive(:confirm).with(include(app)).and_return(true)

      result = run_cpl_command("delete", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Deleting app '#{app}'[.]+? done!/)
      expect(result[:stderr]).not_to include("Unbinding identity from policy")
    end
  end

  context "when identity and policy are bound" do
    let!(:app) { dummy_test_app("secrets") }

    before do
      run_cpl_command!("apply-template", "secrets", "-a", app)
      run_cpl_command!("setup-app", "-a", app)
    end

    it "unbinds identity from policy" do
      allow(Shell).to receive(:confirm).with(include(app)).and_return(true)

      result = run_cpl_command("delete", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Deleting app '#{app}'[.]+? done!/)
      expect(result[:stderr]).to match(/Unbinding identity from policy for app '#{app}'[.]+? done!/)
    end
  end
end
