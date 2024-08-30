# frozen_string_literal: true

require "spec_helper"

describe TerraformConfig::Generator do
  let(:generator) { described_class.new(config: config, template: template) }

  let(:config) { instance_double(Config, org: "org-name", app: "app-name") }

  context "when template's kind is gvc" do
    let(:template) do
      {
        "kind" => "gvc",
        "name" => config.app,
        "description" => "description",
        "tags" => { "tag1" => "tag1_value", "tag2" => "tag2_value" },
        "spec" => {
          "domain" => "app.example.com",
          "env" => [
            {
              "name" => "DATABASE_URL",
              "value" => "postgres://the_user:the_password@postgres.#{config.app}.cpln.local:5432/#{config.app}"
            },
            {
              "name" => "RAILS_ENV",
              "value" => "production"
            },
            {
              "name" => "RAILS_SERVE_STATIC_FILES",
              "value" => "true"
            }
          ],
          "staticPlacement" => {
            "locationLinks" => ["/org/#{config.org}/location/aws-us-east-2"]
          },
          "pullSecretLinks" => ["/org/#{config.org}/secret/some-secret"],
          "loadBalancer" => {
            "dedicated" => true,
            "trustedProxies" => 1
          }
        }
      }
    end

    it "generates correct terraform config and filename for it", :aggregate_failures do
      tf_config = generator.tf_config
      expect(tf_config).to be_an_instance_of(TerraformConfig::Gvc)

      expect(tf_config.name).to eq(config.app)
      expect(tf_config.description).to eq("description")
      expect(tf_config.tags).to eq("tag1" => "tag1_value", "tag2" => "tag2_value")

      expect(tf_config.domain).to eq("app.example.com")
      expect(tf_config.locations).to eq(["aws-us-east-2"])
      expect(tf_config.pull_secrets).to eq(["cpln_secret.some-secret.name"])
      expect(tf_config.env).to eq(
        {
          "DATABASE_URL" => "postgres://the_user:the_password@postgres.#{config.app}.cpln.local:5432/#{config.app}",
          "RAILS_ENV" => "production",
          "RAILS_SERVE_STATIC_FILES" => "true"
        }
      )
      expect(tf_config.load_balancer).to eq({ dedicated: true, trusted_proxies: 1 })

      tf_filename = generator.filename
      expect(tf_filename).to eq("gvc.tf")
    end
  end

  context "when template's kind is identity" do
    let(:template) do
      {
        "kind" => "identity",
        "name" => "identity-name",
        "description" => "description",
        "tags" => { "tag1" => "tag1_value", "tag2" => "tag2_value" }
      }
    end

    it "generates correct terraform config and filename for it", :aggregate_failures do
      tf_config = generator.tf_config
      expect(tf_config).to be_an_instance_of(TerraformConfig::Identity)

      expect(tf_config.name).to eq("identity-name")
      expect(tf_config.description).to eq("description")
      expect(tf_config.tags).to eq("tag1" => "tag1_value", "tag2" => "tag2_value")

      tf_filename = generator.filename
      expect(tf_filename).to eq("identities.tf")
    end
  end
end
