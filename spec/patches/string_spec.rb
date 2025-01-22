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
end
