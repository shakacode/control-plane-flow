# frozen_string_literal: true

require "spec_helper"

RSpec.describe Array do
  describe "#crush" do
    it "returns nil for an empty array" do
      expect([].crush).to be_nil
    end

    it "returns an array of crushed elements" do
      expect([1, 2, 3].crush).to eq([1, 2, 3])
    end

    it "returns nil for array with nil values" do
      expect([nil, nil, nil].crush).to be_nil
    end

    it "returns an array with non-nil values" do
      expect([1, nil, 2, nil, "3"].crush).to eq([1, 2, "3"])
    end

    it "returns an array with non-nil values from hashes" do
      expect([{ a: 1 }, { a: nil }, { b: 2 }].crush).to eq([{ a: 1 }, { b: 2 }])
    end

    it "returns nil if all hashes are nil" do
      expect([{ a: nil }, { b: nil }].crush).to be_nil
    end

    it "returns an array with non-nil values from nested arrays" do
      expect([[1, 2], [nil], [3]].crush).to eq([[1, 2], [3]])
    end

    it "returns nil for an array of empty arrays" do
      expect([[], []].crush).to be_nil
    end

    it "returns an array with non-nil values from mixed types" do
      expect([1, nil, { a: 2 }, [], { b: nil }].crush).to eq([1, { a: 2 }])
    end

    it "handles deeply nested structures" do
      input = [
        { a: [1, { b: 2 }] },
        { c: [nil, { d: nil }] },
        { e: [3, { f: 4 }] }
      ]

      expected = [
        { a: [1, { b: 2 }] },
        { e: [3, { f: 4 }] }
      ]
      expect(input.crush).to eq(expected)
    end
  end
end
