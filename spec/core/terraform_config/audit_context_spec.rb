# frozen_string_literal: true

require "spec_helper"

describe TerraformConfig::AuditContext do
  let(:config) { described_class.new(**options) }

  let(:options) do
    {
      name: "audit-context-name",
      description: "audit context description",
      tags: { "tag1" => "true", "tag2" => "value" }
    }
  end

  describe "#to_tf" do
    subject(:generated) { config.to_tf }

    it "generates correct config" do
      expect(generated).to eq(
        <<~EXPECTED
          resource "cpln_audit_context" "audit-context-name" {
            name = "audit-context-name"
            description = "audit context description"
            tags = {
              tag1 = "true"
              tag2 = "value"
            }
          }
        EXPECTED
      )
    end
  end

  it_behaves_like "importable terraform resource", reference: "cpln_audit_context.audit-context-name"
end
