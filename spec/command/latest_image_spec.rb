# frozen_string_literal: true

require "spec_helper"

describe Command::LatestImage do
  def wait_for_latest_image(app, expected_suffix, attempts: 8, delay: 5)
    expected_output = "#{app}:#{expected_suffix}"
    result = nil

    attempts.times do |attempt|
      result = run_cpflow_command("latest-image", "-a", app)
      return result if result[:status].zero? && result[:stdout].include?(expected_output)

      break unless result[:status].zero? && result[:stdout].include?("#{app}:NO_IMAGE_AVAILABLE")

      sleep(delay) if attempt < attempts - 1
    end

    result
  end

  context "when no images have been built" do
    let!(:app) { dummy_test_app }

    it "displays default image for app" do
      result = run_cpflow_command("latest-image", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("#{app}:NO_IMAGE_AVAILABLE")
    end
  end

  context "when images have been built", :slow do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    it "displays latest image for app" do
      result = wait_for_latest_image(app, 2)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("#{app}:2")
    end
  end
end
