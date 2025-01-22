# frozen_string_literal: true

require "spec_helper"

describe Hash do
  describe "#deep_underscore_keys" do
    subject(:deep_underscored_keys_hash) { hash.deep_underscore_keys }

    context "with an empty hash" do
      let(:hash) { {} }

      it "returns an empty hash" do
        expect(deep_underscored_keys_hash).to eq({})
      end
    end

    context "with a nested hash" do
      let(:hash) { { "outerCamelCase" => { innerCamelCase: "value" } } }

      it "transforms keys at all levels" do
        expect(deep_underscored_keys_hash).to eq("outer_camel_case" => { inner_camel_case: "value" })
      end
    end

    context "with already underscored keys" do
      let(:hash) { { "already_underscored" => "value" } }

      it "leaves underscored keys unchanged" do
        expect(deep_underscored_keys_hash).to eq("already_underscored" => "value")
      end
    end

    context "with keys containing numbers or special characters" do
      let(:hash) { { "camelCase123" => "value1", "special@CaseKey" => "value2" } }

      it "correctly transforms keys with numbers or special characters" do
        expect(deep_underscored_keys_hash).to eq("camel_case123" => "value1", "special@case_key" => "value2")
      end
    end

    context "with string keys" do
      let(:hash) { { "camelCaseKey" => "value1", "snake_case_key" => "value2", "XMLHttpRequest" => "value3" } }

      it "transforms camelCase keys to snake_case" do
        expect(deep_underscored_keys_hash["camel_case_key"]).to eq("value1")
      end

      it "leaves snake_case keys unchanged" do
        expect(deep_underscored_keys_hash["snake_case_key"]).to eq("value2")
      end

      it "correctly handles keys with multiple uppercase letters" do
        expect(deep_underscored_keys_hash["xml_http_request"]).to eq("value3")
      end
    end

    context "with symbol keys" do
      let(:hash) { { camelCaseKey: "value1", snake_case_key: "value2", XMLHttpRequest: "value3" } }

      it "transforms camelCase symbol keys to snake_case" do
        expect(deep_underscored_keys_hash[:camel_case_key]).to eq("value1")
      end

      it "leaves snake_case symbol keys unchanged" do
        expect(deep_underscored_keys_hash[:snake_case_key]).to eq("value2")
      end

      it "correctly handles symbol keys with multiple uppercase letters" do
        expect(deep_underscored_keys_hash[:xml_http_request]).to eq("value3")
      end
    end
  end

  describe "#crush" do
    it "returns nil when all values are nil" do
      expect({ a: nil, b: nil }.crush).to be_nil
    end

    it "removes nil values from the hash" do
      expect({ a: 1, b: nil, c: 3 }.crush).to eq({ a: 1, c: 3 })
    end

    it "crushes nested hashes" do
      nested_hash = { a: { b: nil, c: 2 }, d: 4 }
      expect(nested_hash.crush).to eq({ a: { c: 2 }, d: 4 })
    end

    it "handles non-hash values" do
      expect({ a: 1, b: "string", c: nil }.crush).to eq({ a: 1, b: "string" })
    end

    it "returns nil for empty hash" do
      expect({}.crush).to be_nil
    end

    it "removes nil values from an array in the hash" do
      expect({ a: [1, nil, 3], b: nil }.crush).to eq({ a: [1, 3] })
    end

    it "crushes nested hashes within an array" do
      expect({ a: [{ b: nil, c: 2 }, { d: nil }], e: 4 }.crush).to eq({ a: [{ c: 2 }], e: 4 })
    end

    it "handles arrays with mixed values" do
      expect({ a: [1, nil, { b: nil, c: 3 }], d: 4 }.crush).to eq({ a: [1, { c: 3 }], d: 4 })
    end

    it "removes array if it contains only nil values" do
      expect({ a: [nil, nil], b: 1 }.crush).to eq({ b: 1 })
    end
  end
end
