# frozen_string_literal: true

require "spec_helper"

describe TerraformConfig::RequiredProvider do
  let(:config) { described_class.new(name: name, org: org, **options) }

  describe "#to_tf" do
    subject(:generated) { config.to_tf }

    context "when provider is cpln" do
      let(:name) { "cpln" }
      let(:org) { "test-org" }
      let(:options) { { source: "controlplane-com/cpln", version: "~> 1.0" } }

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            terraform {
              cloud {
                organization = "test-org"
              }
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
  end
end
