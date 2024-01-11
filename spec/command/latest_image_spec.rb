# frozen_string_literal: true

require "spec_helper"

describe Command::LatestImage do
  context "when no images have been built" do
    let!(:app) { dummy_test_app }

    it "displays default image for app", :fast do
      result = run_cpl_command("latest-image", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("#{app}:NO_IMAGE_AVAILABLE")
    end
  end

  context "when images have been built" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    it "displays latest image for app", :fast do
      result = run_cpl_command("latest-image", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("#{app}:2")
    end
  end
end
