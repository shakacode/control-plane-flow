# frozen_string_literal: true

require "spec_helper"

describe Hash do
  describe "#underscore_keys" do
    subject(:underscored_keys_hash) { hash.underscore_keys }

    context "with an empty hash" do
      let(:hash) { {} }

      it "returns an empty hash" do
        expect(underscored_keys_hash).to eq({})
      end
    end

    context "with a nested hash" do
      let(:hash) { { "outerCamelCase" => { innerCamelCase: "value" } } }

      it "transforms keys only at top level" do
        expect(underscored_keys_hash).to eq("outer_camel_case" => { innerCamelCase: "value" })
      end
    end

    context "with already underscored keys" do
      let(:hash) { { "already_underscored" => "value" } }

      it "leaves underscored keys unchanged" do
        expect(underscored_keys_hash).to eq("already_underscored" => "value")
      end
    end

    context "with keys containing numbers or special characters" do
      let(:hash) { { "camelCase123" => "value1", "special@CaseKey" => "value2" } }

      it "correctly transforms keys with numbers or special characters" do
        expect(underscored_keys_hash).to eq("camel_case123" => "value1", "special@case_key" => "value2")
      end
    end

    context "with string keys" do
      let(:hash) { { "camelCaseKey" => "value1", "snake_case_key" => "value2", "XMLHttpRequest" => "value3" } }

      it "transforms camelCase keys to snake_case" do
        expect(underscored_keys_hash["camel_case_key"]).to eq("value1")
      end

      it "leaves snake_case keys unchanged" do
        expect(underscored_keys_hash["snake_case_key"]).to eq("value2")
      end

      it "correctly handles keys with multiple uppercase letters" do
        expect(underscored_keys_hash["xml_http_request"]).to eq("value3")
      end
    end

    context "with symbol keys" do
      let(:hash) { { camelCaseKey: "value1", snake_case_key: "value2", XMLHttpRequest: "value3" } }

      it "transforms camelCase symbol keys to snake_case" do
        expect(underscored_keys_hash[:camel_case_key]).to eq("value1")
      end

      it "leaves snake_case symbol keys unchanged" do
        expect(underscored_keys_hash[:snake_case_key]).to eq("value2")
      end

      it "correctly handles symbol keys with multiple uppercase letters" do
        expect(underscored_keys_hash[:xml_http_request]).to eq("value3")
      end
    end
  end
end
