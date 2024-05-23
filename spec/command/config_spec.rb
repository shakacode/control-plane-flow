# frozen_string_literal: true

require "spec_helper"

describe Command::Config do
  context "when no app is provided" do
    it "displays config for each app" do
      result = run_cpl_command("config")

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("Config for app 'dummy-test-#{dummy_test_app_global_identifier}'")
      expect(result[:stdout]).to include("Config for app 'dummy-test-nothing-#{dummy_test_app_global_identifier}'")
      expect(result[:stdout]).to match(/^  match_if_app_name_starts_with: true$/)
      expect(result[:stdout]).to match(/^    - rails$/)
    end
  end

  context "when app is provided" do
    let!(:app) { dummy_test_app }

    it "displays config for specific app" do
      result = run_cpl_command("config", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("Current config (app '#{app}')")
      expect(result[:stdout]).to match(/^  match_if_app_name_starts_with: true$/)
      expect(result[:stdout]).to match(/^    - rails$/)
    end
  end
end
