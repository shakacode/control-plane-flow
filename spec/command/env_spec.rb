# frozen_string_literal: true

require "spec_helper"

describe Command::Env do
  context "when app does not exist" do
    let!(:app) { dummy_test_app }

    it "raises error" do
      result = run_cpl_command("env", "-a", app)

      expect(result[:status]).to eq(1)
      expect(result[:stderr]).to include("Can't find app '#{app}'")
    end
  end

  context "when app exists" do
    let!(:app) { dummy_test_app("default", create_if_not_exists: true) }

    it "displays app-specific environment variables" do
      result = run_cpl_command("env", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stdout])
        .to include("DATABASE_URL=postgres://postgres:password@postgres.#{app}.cpln.local:5432/#{app}")
    end
  end
end
