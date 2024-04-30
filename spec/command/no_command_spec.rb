# frozen_string_literal: true

require "spec_helper"

describe Command::NoCommand do
  context "when called with nothing" do
    it "displays help" do
      result = run_cpl_command

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("cpl commands")
    end
  end

  context "when called with --version" do
    it "displays version" do
      result = run_cpl_command("--version")

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include(Cpl::VERSION)
    end
  end
end
