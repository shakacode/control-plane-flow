# frozen_string_literal: true

require "spec_helper"

describe TerraformConfig::Provider do
  let(:config) { described_class.new(name: name, **options) }

  context "when provider is cpln" do
    let(:name) { "cpln" }
    let(:options) { { org: "test-org" } }

    describe "#to_tf" do
      subject(:generated) { config.to_tf }

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

    it_behaves_like "unimportable terraform resource"
  end
end
