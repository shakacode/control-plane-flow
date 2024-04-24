# frozen_string_literal: true

require "spec_helper"

describe Command::CleanupStaleApps do
  let!(:app_prefix) { dummy_test_app_prefix("with-stale-app-image-deployed-days") }

  context "when 'stale_app_image_deployed_days' is not defined" do
    let!(:app) { dummy_test_app("with-nothing") }

    it "raises error" do
      result = run_cpl_command("cleanup-stale-apps", "-a", app)

      expect(result[:status]).to eq(1)
      expect(result[:stderr]).to include("Can't find option 'stale_app_image_deployed_days'")
    end
  end

  context "when there are no stale apps to delete" do
    let!(:app) { dummy_test_app }

    it "displays message" do
      result = run_cpl_command("cleanup-stale-apps", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("No stale apps found")
    end
  end

  context "when there are stale apps to delete" do
    let!(:app1) { dummy_test_app("with-stale-app-image-deployed-days") }
    let!(:app2) { dummy_test_app("with-stale-app-image-deployed-days") }

    before do
      run_cpl_command!("apply-template", "gvc", "-a", app1)
      run_cpl_command!("apply-template", "gvc", "-a", app2)
      run_cpl_command!("build-image", "-a", app1)
      run_cpl_command!("build-image", "-a", app2)
    end

    after do
      run_cpl_command!("delete", "-a", app1, "--yes")
      run_cpl_command!("delete", "-a", app2, "--yes")
    end

    it "asks for confirmation and does nothing", :slow do
      allow(Shell).to receive(:confirm).with(include("2 apps")).and_return(false)

      travel_to_days_later(30)
      result = run_cpl_command("cleanup-stale-apps", "-a", app_prefix)
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).not_to include("Deleting app")
    end

    it "asks for confirmation and deletes stale apps", :slow do
      allow(Shell).to receive(:confirm).with(include("2 apps")).and_return(true)

      travel_to_days_later(30)
      result = run_cpl_command("cleanup-stale-apps", "-a", app_prefix)
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Deleting app '#{app1}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting image '#{app1}:1'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting app '#{app2}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting image '#{app2}:1'[.]+? done!/)
    end

    it "skips confirmation and deletes stale apps", :slow do
      allow(Shell).to receive(:confirm).and_return(false)

      travel_to_days_later(30)
      result = run_cpl_command("cleanup-stale-apps", "-a", app_prefix, "--yes")
      travel_back

      expect(Shell).not_to have_received(:confirm)
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Deleting app '#{app1}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting image '#{app1}:1'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting app '#{app2}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting image '#{app2}:1'[.]+? done!/)
    end
  end

  context "with multiple apps" do
    let!(:app1) { dummy_test_app("with-stale-app-image-deployed-days") }
    let!(:app2) { dummy_test_app("with-stale-app-image-deployed-days") }
    let!(:app3) { dummy_test_app("with-stale-app-image-deployed-days") }
    let!(:app4) { dummy_test_app("with-stale-app-image-deployed-days") }

    before do
      run_cpl_command!("apply-template", "gvc", "-a", app1)
      run_cpl_command!("apply-template", "gvc", "-a", app2)
      run_cpl_command!("apply-template", "gvc", "-a", app3)
      run_cpl_command!("apply-template", "gvc", "-a", app4)
    end

    after do
      run_cpl_command!("delete", "-a", app1, "--yes")
      run_cpl_command!("delete", "-a", app2, "--yes")
      run_cpl_command!("delete", "-a", app3, "--yes")
      run_cpl_command!("delete", "-a", app4, "--yes")
    end

    it "lists correct stale apps", :slow do
      allow(Shell).to receive(:confirm).with(include("2 apps")).and_return(false)

      # We need to stub the image from app3 to have the current date,
      # as Control Plane does not allow manipulating the creation date of an image
      allow_any_instance_of(Controlplane).to receive(:query_images).and_wrap_original do |original, *args, &block| # rubocop:disable RSpec/AnyInstance
        original_return = original.call(*args, &block)
        original_return["items"].each do |item|
          item["created"] = Time.now.to_s if item["name"].start_with?("#{app3}:")
        end
        original_return
      end

      # Apps with old image, will be listed
      run_cpl_command!("build-image", "-a", app1)
      run_cpl_command!("build-image", "-a", app2)
      travel_to_days_later(30)
      # App with new image, wont't be listed
      run_cpl_command!("build-image", "-a", app3)
      result = run_cpl_command("cleanup-stale-apps", "-a", app_prefix)
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("- #{app1}")
      expect(result[:stderr]).to include("- #{app2}")
      expect(result[:stderr]).not_to include("- #{app3}")
      expect(result[:stderr]).not_to include("- #{app4}")
    end
  end
end
