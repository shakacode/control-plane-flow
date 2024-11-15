# frozen_string_literal: true

require "spec_helper"

describe TerraformConfig::RequiredProvider do
  let(:config) { described_class.new(name: name, org: org, **options) }

  context "when provider is cpln" do
    let(:name) { "cpln" }
    let(:org) { "test-org" }
    let(:options) { { source: "controlplane-com/cpln", version: "~> 1.0" } }

    describe "#to_tf" do
      subject(:generated) { config.to_tf }

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            terraform {
              required_providers {
                cpln = {
                  source = "controlplane-com/cpln"
                  version = "~> 1.0"
                }
              }
            }
          EXPECTED
        )
      end
    end

    it_behaves_like "unimportable terraform resource"
  end
end
