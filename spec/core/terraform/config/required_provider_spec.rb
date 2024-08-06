# frozen_string_literal: true

require "spec_helper"

describe Terraform::Config::RequiredProvider do
  let(:config) { described_class.new(name, **options) }

  describe "#to_tf" do
    subject(:generated) { config.to_tf }

    context "when provider is cpln" do
      let(:name) { "cpln" }
      let(:options) { { source: "controlplane-com/cpln", version: "~> 1.0" } }

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
  end
end
