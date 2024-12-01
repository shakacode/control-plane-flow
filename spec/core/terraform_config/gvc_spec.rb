# frozen_string_literal: true

require "spec_helper"

describe TerraformConfig::Gvc do
  let(:config) { described_class.new(**options) }

  let(:options) do
    {
      name: "gvc-name",
      description: "gvc description",
      domain: "app.example.com",
      env: { "var1" => "value", "var2" => 1 },
      tags: { "tag1" => "tag_value", "tag2" => true },
      locations: %w[aws-us-east-1 aws-us-east-2],
      pull_secrets: ["cpln_secret.docker.name"],
      load_balancer: { "dedicated" => true, "trustedProxies" => 1 }
    }
  end

  describe "#to_tf" do
    subject(:generated) { config.to_tf }

    it "generates correct config" do
      expect(generated).to eq(
        <<~EXPECTED
          resource "cpln_gvc" "gvc-name" {
            name = "gvc-name"
            description = "gvc description"
            tags = {
              tag1 = "tag_value"
              tag2 = true
            }
            domain = "app.example.com"
            locations = ["aws-us-east-1", "aws-us-east-2"]
            pull_secrets = [cpln_secret.docker.name]
            env = {
              var1 = "value"
              var2 = 1
            }
            load_balancer {
              dedicated = true
              trusted_proxies = 1
            }
          }
        EXPECTED
      )
    end
  end

  it_behaves_like "importable terraform resource", reference: "cpln_gvc.gvc-name"
end
