# frozen_string_literal: true

require "rspec"

RSpec.describe Object do
  describe "#crush" do
    it "returns the object itself" do
      obj = described_class.new
      expect(obj.crush).to eq(obj)
    end
  end
end
