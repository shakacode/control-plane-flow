# frozen_string_literal: true

require "spec_helper"

describe TerraformConfig::Identity do
  let(:config) { described_class.new(**options) }

  describe "#to_tf" do
    subject(:generated) { config.to_tf }

    let(:options) do
      {
        gvc: "cpln_gvc.some-gvc.name",
        name: "identity-name",
        description: "identity description",
        tags: { "tag1" => "true", "tag2" => "false" }
      }
    end

    it "generates correct config" do
      expect(generated).to eq(
        <<~EXPECTED
          resource "cpln_identity" "identity-name" {
            gvc = cpln_gvc.some-gvc.name
            name = "identity-name"
            description = "identity description"
            tags = {
              tag1 = "true"
              tag2 = "false"
            }
          }
        EXPECTED
      )
    end
  end
end
