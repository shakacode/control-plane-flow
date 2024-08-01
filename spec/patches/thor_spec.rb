# frozen_string_literal: true

require "thor"
require "patches/thor"

describe Thor do
  describe ".basename" do
    subject(:basename) { klass.send(:basename) }

    context "when class has defined package name" do
      let(:klass) do
        Class.new(described_class) do
          package_name "test_package_name"
        end
      end

      it "returns package name" do
        expect(basename).to eq("test_package_name")
      end
    end

    context "when class doesn't have defined package name" do
      let(:klass) { Class.new(described_class) }

      it "returns basename of program invoking the class" do
        expect(basename).to eq("rspec")
      end
    end
  end
end
