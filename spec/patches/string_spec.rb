# frozen_string_literal: true

require "spec_helper"

RSpec.describe String do
  describe "#pluralize" do
    context "when word is empty" do
      it "returns an empty string" do
        expect("".pluralize).to eq("")
      end
    end

    context "when word already ends with 'ies'" do
      it "returns the word unchanged" do
        expect("cities".pluralize).to eq("cities")
        expect("babies".pluralize).to eq("babies")
      end
    end

    context "when word ends with 's', 'x', 'z', 'ch', or 'sh'" do
      it "adds 'es' to the end if it doesn't already end with 'es'" do
        expect("bus".pluralize).to eq("buses")
        expect("box".pluralize).to eq("boxes")
        expect("buzz".pluralize).to eq("buzzes")
        expect("church".pluralize).to eq("churches")
        expect("dish".pluralize).to eq("dishes")
      end

      it "returns the word unchanged if it already ends with 'es'" do
        expect("buses".pluralize).to eq("buses")
        expect("boxes".pluralize).to eq("boxes")
      end
    end

    context "when word ends with 'y'" do
      it "changes 'y' to 'ies'" do
        expect("city".pluralize).to eq("cities")
        expect("baby".pluralize).to eq("babies")
      end
    end

    context "when word doesn't end with 'y', 's', 'x', 'z', 'ch', or 'sh'" do
      it "adds 's' to the end if it doesn't already end with 's'" do
        expect("cat".pluralize).to eq("cats")
        expect("dog".pluralize).to eq("dogs")
        expect("book".pluralize).to eq("books")
      end
    end

    context "when word is a single character" do
      it "applies the rules correctly" do
        expect("a".pluralize).to eq("as")
        expect("s".pluralize).to eq("ses")
        expect("x".pluralize).to eq("xes")
        expect("y".pluralize).to eq("ies")
      end
    end
  end
end
