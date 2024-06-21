# frozen_string_literal: true

require "spec_helper"

describe Command::CleanupImages do
  context "when 'image_retention_max_qty' or 'image_retention_days' are not defined" do
    let!(:app) { dummy_test_app("nothing") }

    it "raises error" do
      result = run_cpflow_command("cleanup-images", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find either option 'image_retention_max_qty' or 'image_retention_days'")
    end
  end

  context "when there are no images to delete" do
    let!(:app) { dummy_test_app }

    it "displays message" do
      result = run_cpflow_command("cleanup-images", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("No images to delete")
    end
  end

  context "when app does not exist" do
    let!(:app) { dummy_test_app }

    before do
      run_cpflow_command!("build-image", "-a", app) # app:1
    end

    it "deletes leftover images", :slow do
      allow(Shell).to receive(:confirm).with(include("1 images")).and_return(true)

      travel_to_days_later(30)
      result = run_cpflow_command("cleanup-images", "-a", app)
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Deleting image '#{app}:1'[.]+? done!/)
    end
  end

  context "when app exists" do
    let!(:app) { dummy_test_app }

    before do
      run_cpflow_command!("apply-template", "app", "-a", app)
      run_cpflow_command!("build-image", "-a", app) # app:1
      run_cpflow_command!("build-image", "-a", app) # app:2
    end

    after do
      run_cpflow_command!("delete", "-a", app, "--yes")
    end

    it "asks for confirmation and does nothing", :slow do
      allow(Shell).to receive(:confirm).with(include("1 images")).and_return(false)

      travel_to_days_later(30)
      result = run_cpflow_command("cleanup-images", "-a", app)
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).not_to include("Deleting image")
    end

    it "asks for confirmation and deletes images", :slow do
      allow(Shell).to receive(:confirm).with(include("1 images")).and_return(true)

      travel_to_days_later(30)
      result = run_cpflow_command("cleanup-images", "-a", app)
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Deleting image '#{app}:1'[.]+? done!/)
    end

    it "skips confirmation and deletes images", :slow do
      allow(Shell).to receive(:confirm).and_return(false)

      travel_to_days_later(30)
      result = run_cpflow_command("cleanup-images", "-a", app, "--yes")
      travel_back

      expect(Shell).not_to have_received(:confirm)
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Deleting image '#{app}:1'[.]+? done!/)
    end
  end

  context "with single app based on max quantity" do
    let!(:app) { dummy_test_app("image-retention-max-qty") }

    before do
      run_cpflow_command!("apply-template", "app", "-a", app)
    end

    after do
      run_cpflow_command!("delete", "-a", app, "--yes")
    end

    it "lists correct images", :slow do
      allow(Shell).to receive(:confirm).with(include("2 images")).and_return(false)

      # Excess images, will be listed
      run_cpflow_command!("build-image", "-a", app) # app:1
      run_cpflow_command!("build-image", "-a", app) # app:2
      # Images that don't exceed max quantity of 3, won't be listed
      run_cpflow_command!("build-image", "-a", app) # app:3
      run_cpflow_command!("build-image", "-a", app) # app:4
      run_cpflow_command!("build-image", "-a", app) # app:5
      # Latest image, excluded from max quantity calculation, won't be listed
      run_cpflow_command!("build-image", "-a", app) # app:6
      result = run_cpflow_command("cleanup-images", "-a", app)

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/- #{app}:1 \(.+? - exceeds max quantity of 3\)/)
      expect(result[:stderr]).to match(/- #{app}:2 \(.+? - exceeds max quantity of 3\)/)
    end
  end

  context "with single app based on days" do
    let!(:app) { dummy_test_app("image-retention-days") }

    before do
      run_cpflow_command!("apply-template", "app", "-a", app)
    end

    after do
      run_cpflow_command!("delete", "-a", app, "--yes")
    end

    it "lists correct images", :slow do
      allow(Shell).to receive(:confirm).with(include("2 images")).and_return(false)

      # Old images, will be listed
      run_cpflow_command!("build-image", "-a", app) # app:1
      run_cpflow_command!("build-image", "-a", app) # app:2
      # Latest image, excluded from days calculation, won't be listed
      run_cpflow_command!("build-image", "-a", app) # app:3
      travel_to_days_later(30)
      result = run_cpflow_command("cleanup-images", "-a", app)
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/- #{app}:1 \(.+? - older than 30 days\)/)
      expect(result[:stderr]).to match(/- #{app}:2 \(.+? - older than 30 days\)/)
    end
  end

  context "with multiple apps" do
    let!(:app_prefix) { dummy_test_app_prefix("image-retention") }
    let!(:app1) { dummy_test_app("image-retention", "1", create_if_not_exists: true) }
    let!(:app2) { dummy_test_app("image-retention", "2", create_if_not_exists: true) }

    it "lists correct images from exact app", :slow do
      allow(Shell).to receive(:confirm).with(include("2 images")).and_return(false)

      travel_to_days_later(30)
      result = run_cpflow_command("cleanup-images", "-a", app1)
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/- #{app1}:1 \(.+? - older than 30 days\)/)
      expect(result[:stderr]).to match(/- #{app1}:2 \(.+? - older than 30 days\)/)
    end

    it "lists correct images from all matching apps", :slow do
      allow(Shell).to receive(:confirm).with(include("4 images")).and_return(false)

      travel_to_days_later(30)
      result = run_cpflow_command("cleanup-images", "-a", app_prefix)
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/- #{app1}:1 \(.+? - older than 30 days\)/)
      expect(result[:stderr]).to match(/- #{app1}:2 \(.+? - older than 30 days\)/)
      expect(result[:stderr]).to match(/- #{app2}:1 \(.+? - older than 30 days\)/)
      expect(result[:stderr]).to match(/- #{app2}:2 \(.+? - older than 30 days\)/)
    end
  end
end
