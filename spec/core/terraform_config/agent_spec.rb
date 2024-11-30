# frozen_string_literal: true

require "spec_helper"

describe TerraformConfig::Agent do
  let(:config) { described_class.new(**options) }

  let(:options) do
    {
      name: "agent-name",
      description: "agent description",
      tags: { "tag1" => "true", "tag2" => "value" }
    }
  end

  describe "#to_tf" do
    subject(:generated) { config.to_tf }

    it "generates correct config" do
      expect(generated).to eq(
        <<~EXPECTED
          resource "cpln_agent" "agent-name" {
            name = "agent-name"
            description = "agent description"
            tags = {
              tag1 = "true"
              tag2 = "value"
            }
          }
        EXPECTED
      )
    end
  end

  it_behaves_like "importable terraform resource"

  describe "#reference" do
    subject { config.reference }

    it { is_expected.to eq("cpln_agent.agent-name") }
  end
end
