# frozen_string_literal: true

require "spec_helper"

describe Config do
  describe "#use_digest_image_ref?" do
    let(:config) do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, options)
      allow(instance).to receive(:current).and_return(current)
      instance
    end

    context "when CLI flag is true" do
      let(:options) { { use_digest_image_ref: true } }
      let(:current) { { use_digest_image_ref: false } }

      it "returns true even if YAML is false" do
        expect(config.use_digest_image_ref?).to be(true)
      end
    end

    context "when CLI flag is false" do
      let(:options) { { use_digest_image_ref: false } }
      let(:current) { { use_digest_image_ref: true } }

      it "returns false even if YAML is true" do
        expect(config.use_digest_image_ref?).to be(false)
      end
    end

    context "when CLI flag is absent" do
      let(:options) { {} }

      context "with YAML use_digest_image_ref set to true" do
        let(:current) { { use_digest_image_ref: true } }

        it "returns true" do
          expect(config.use_digest_image_ref?).to be(true)
        end
      end

      context "with YAML use_digest_image_ref set to false" do
        let(:current) { { use_digest_image_ref: false } }

        it "returns false" do
          expect(config.use_digest_image_ref?).to be(false)
        end
      end

      context "without use_digest_image_ref in YAML" do
        let(:current) { {} }

        it "returns false" do
          expect(config.use_digest_image_ref?).to be(false)
        end
      end

      context "without a current app config" do
        let(:current) { nil }

        it "returns false" do
          expect(config.use_digest_image_ref?).to be(false)
        end
      end
    end
  end
end
