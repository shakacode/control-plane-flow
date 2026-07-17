# frozen_string_literal: true

require "spec_helper"

describe Helpers do
  describe ".strip_str_and_validate" do
    it "returns nil for nil" do
      expect(described_class.strip_str_and_validate(nil)).to be_nil
    end

    it "returns nil for a blank string" do
      expect(described_class.strip_str_and_validate("   \n")).to be_nil
    end

    it "strips surrounding whitespace" do
      expect(described_class.strip_str_and_validate("  my-org \n")).to eq("my-org")
    end

    it "returns an already-clean string unchanged" do
      expect(described_class.strip_str_and_validate("my-org")).to eq("my-org")
    end
  end

  describe ".random_four_digits" do
    it "returns a number between 1000 and 9999" do
      expect(described_class.random_four_digits).to be_between(1000, 9999)
    end

    it "draws from SecureRandom over the four-digit range" do
      allow(SecureRandom).to receive(:random_number).with(1000..9999).and_return(1234)

      expect(described_class.random_four_digits).to eq(1234)
    end
  end

  describe ".normalize_command_name" do
    it "converts underscores to dashes" do
      expect(described_class.normalize_command_name(:deploy_image)).to eq("deploy-image")
    end

    it "leaves names without underscores unchanged" do
      expect(described_class.normalize_command_name("ps")).to eq("ps")
    end
  end

  describe ".normalize_option_name" do
    it "converts the name to a long option flag" do
      expect(described_class.normalize_option_name(:staging_branch)).to eq("--staging-branch")
    end
  end
end
