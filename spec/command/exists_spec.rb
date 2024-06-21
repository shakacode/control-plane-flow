# frozen_string_literal: true

require "spec_helper"

describe Command::Exists do
  context "when app does not exist" do
    let!(:app) { dummy_test_app }

    it "exits with non-zero status" do
      result = run_cpflow_command("exists", "-a", app)

      expect(result[:status]).not_to eq(0)
    end
  end

  context "when app exists" do
    let!(:app) { dummy_test_app("default", create_if_not_exists: true) }

    it "exits with zero status" do
      result = run_cpflow_command("exists", "-a", app)

      expect(result[:status]).to eq(0)
    end
  end
end
