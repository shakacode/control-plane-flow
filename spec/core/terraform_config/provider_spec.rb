# frozen_string_literal: true

require "spec_helper"

describe TerraformConfig::Provider do
  let(:config) { described_class.new(name, **options) }

  describe "#to_tf" do
    subject(:generated) { config.to_tf }

    context "when provider is cpln" do
      let(:name) { "cpln" }
      let(:options) { { org: "test-org" } }

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            provider "cpln" {
              org = "test-org"
            }
          EXPECTED
        )
      end
    end
  end
end
