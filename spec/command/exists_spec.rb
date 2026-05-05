# frozen_string_literal: true

require "spec_helper"

describe Command::Exists do
  before do
    allow_any_instance_of(Controlplane).to receive(:ensure_org_exists!) # rubocop:disable RSpec/AnyInstance
  end

  it "uses an unambiguous not-found exit code" do
    expect(ExitCode::NOT_FOUND).to eq(3)
  end

  context "when app does not exist" do
    let(:app) { dummy_test_app("default") }

    it "exits with the not-found status" do
      allow_any_instance_of(Controlplane).to receive(:fetch_gvc).and_return(nil) # rubocop:disable RSpec/AnyInstance

      result = run_cpflow_command("exists", "-a", app)

      expect(result[:status]).to eq(ExitCode::NOT_FOUND)
    end
  end

  context "when app exists" do
    let(:app) { dummy_test_app("default") }

    it "exits with zero status" do
      allow_any_instance_of(Controlplane).to receive(:fetch_gvc).and_return({ "name" => app }) # rubocop:disable RSpec/AnyInstance

      result = run_cpflow_command("exists", "-a", app)

      expect(result[:status]).to eq(0)
    end
  end

  context "when app lookup errors" do
    let(:app) { dummy_test_app("default") }

    it "exits with the default error status" do
      allow_any_instance_of(Controlplane).to receive(:fetch_gvc).and_raise("network unavailable") # rubocop:disable RSpec/AnyInstance

      result = run_cpflow_command("exists", "-a", app)

      expect(result[:status]).to eq(ExitCode::ERROR_DEFAULT)
      expect(result[:stderr]).to include("network unavailable")
    end
  end
end
