# frozen_string_literal: true

require "spec_helper"

RSpec.describe String do
  describe "#pluralize" do
    context "when word is empty" do
      it "returns an empty string" do
        expect("".pluralize).to eq("")
      end
    end

    context "when word ends with 'y'" do
      it "changes 'y' to 'ies'" do
        expect("policy".pluralize).to eq("policies")
        expect("identity".pluralize).to eq("identities")
      end
    end

    context "when word does not end with 'y'" do
      it "adds 's' to the end of the word" do
        expect("secret".pluralize).to eq("secrets")
        expect("volumeset".pluralize).to eq("volumesets")
      end
    end
  end

  describe "#unindent" do
    it "strips leading indentation common to all lines" do
      indented = "  first line\n    second line\n"

      expect(indented.unindent).to eq("first line\n  second line\n")
    end
  end

  describe "#underscore" do
    it "converts camel case to underscore format" do
      expect("ControlPlaneFlow".underscore).to eq("control_plane_flow")
    end

    it "converts double colons to forward slashes" do
      expect("Cpflow::Cli".underscore).to eq("cpflow/cli")
    end

    it "handles hyphenated words" do
      expect("control-plane".underscore).to eq("control_plane")
    end
  end

  describe "#indent" do
    it "indents lines by the specified amount" do
      expect("hello\nworld".indent(2)).to eq("  hello\n  world")
    end

    it "uses custom indent character when provided" do
      expect("hello".indent(1, "\t")).to eq("\thello")
    end
  end
end
