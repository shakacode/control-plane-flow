# frozen_string_literal: true

require "spec_helper"

describe Hash do
  describe "#underscore_keys" do
    subject(:underscored_keys_hash) { hash.underscore_keys }

    context "with string keys" do
      let(:hash) { { "camelCaseKey" => "value", "snake_case_key" => "value" } }

      it "returns underscored string keys" do
        expect(underscored_keys_hash).to eq("camel_case_key" => "value", "snake_case_key" => "value")
      end
    end

    context "with symbol keys" do
      let(:hash) { { camelCaseKey: "value", snake_case_key: "value" } }

      it "returns underscored symbol keys" do
        expect(underscored_keys_hash).to eq(camel_case_key: "value", snake_case_key: "value")
      end
    end
  end
end
