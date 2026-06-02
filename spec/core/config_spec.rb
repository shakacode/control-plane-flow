# frozen_string_literal: true

require "spec_helper"

describe Config do
  describe "#shared_secret_grants" do
    def build_config(current)
      instance = described_class.allocate
      allow(instance).to receive(:current).and_return(current)
      instance
    end

    it "defaults to no shared secret grants" do
      config = build_config({})

      expect(config.shared_secret_grants).to eq([])
    end

    it "normalizes shared secret grant config" do
      config = build_config(
        {
          shared_secret_grants: [
            {
              name: "database",
              secret_name: "shared-database-secrets",
              policy_name: "shared-database-secrets-policy"
            }
          ]
        }
      )

      expect(config.shared_secret_grants).to eq(
        [
          {
            name: "database",
            secret_name: "shared-database-secrets",
            policy_name: "shared-database-secrets-policy"
          }
        ]
      )
    end

    it "raises when shared secret grants are not an array" do
      config = build_config({ shared_secret_grants: { name: "database" } })

      expect { config.shared_secret_grants }
        .to raise_error("shared_secret_grants for app config must be an array.")
    end

    it "raises when a grant is missing required keys" do
      config = build_config({ shared_secret_grants: [{ name: "database", secret_name: "shared-db" }] })

      expect { config.shared_secret_grants }
        .to raise_error("shared_secret_grants entry 'database' must include policy_name.")
    end

    it "raises when a grant name is not lower snake case" do
      config = build_config(
        {
          shared_secret_grants: [
            {
              name: "DATABASE",
              secret_name: "shared-database-secrets",
              policy_name: "shared-database-secrets-policy"
            }
          ]
        }
      )

      expect { config.shared_secret_grants }
        .to raise_error("shared_secret_grants entry name 'DATABASE' must be lower snake case.")
    end

    it "raises when a shared policy name is not a Control Plane resource name" do
      config = build_config(
        {
          shared_secret_grants: [
            {
              name: "database",
              secret_name: "shared-database-secrets",
              policy_name: "shared-database-secrets-policy;echo nope"
            }
          ]
        }
      )

      expect { config.shared_secret_grants }
        .to raise_error(
          "shared_secret_grants entry 'database' policy_name " \
          "'shared-database-secrets-policy;echo nope' must be a Control Plane resource name."
        )
    end

    it "raises when grant names are duplicated" do
      config = build_config(
        {
          shared_secret_grants: [
            {
              name: "database",
              secret_name: "shared-database-secrets",
              policy_name: "shared-database-secrets-policy"
            },
            {
              name: "database",
              secret_name: "other-database-secrets",
              policy_name: "other-database-secrets-policy"
            }
          ]
        }
      )

      expect { config.shared_secret_grants }
        .to raise_error("shared_secret_grants entry name 'database' must be unique.")
    end
  end

  describe "#shared_secret_placeholders" do
    def build_config(current)
      instance = described_class.allocate
      allow(instance).to receive(:current).and_return(current)
      instance
    end

    it "maps grant names to template placeholders" do
      config = build_config(
        {
          shared_secret_grants: [
            {
              name: "database",
              secret_name: "shared-database-secrets",
              policy_name: "shared-database-secrets-policy"
            },
            {
              name: "license_key",
              secret_name: "shared-license-secrets",
              policy_name: "shared-license-secrets-policy"
            }
          ]
        }
      )

      expect(config.shared_secret_placeholders).to eq(
        "{{SHARED_SECRET_DATABASE}}" => "shared-database-secrets",
        "{{SHARED_SECRET_LICENSE_KEY}}" => "shared-license-secrets"
      )
    end
  end

  describe "#use_digest_image_ref?" do
    def build_config(options:, current:)
      instance = described_class.allocate
      instance.instance_variable_set(:@options, options)
      allow(instance).to receive(:current).and_return(current)
      instance
    end

    let(:config) { build_config(options: options, current: current) }

    context "when CLI flag is true" do
      let(:options) { { use_digest_image_ref: true } }
      let(:current) { { use_digest_image_ref: false } }

      it "returns true even if YAML is false" do
        expect(config.use_digest_image_ref?).to be(true)
      end
    end

    context "when CLI flag is false" do
      let(:options) { { use_digest_image_ref: false } }
      let(:current) { { use_digest_image_ref: true } }

      it "returns false even if YAML is true" do
        expect(config.use_digest_image_ref?).to be(false)
      end
    end

    context "when CLI flag is absent" do
      let(:options) { {} }

      context "with YAML use_digest_image_ref set to true" do
        let(:current) { { use_digest_image_ref: true } }

        it "returns true" do
          expect(config.use_digest_image_ref?).to be(true)
        end
      end

      context "with YAML use_digest_image_ref set to false" do
        let(:current) { { use_digest_image_ref: false } }

        it "returns false" do
          expect(config.use_digest_image_ref?).to be(false)
        end
      end

      context "without use_digest_image_ref in YAML" do
        let(:current) { {} }

        it "returns false" do
          expect(config.use_digest_image_ref?).to be(false)
        end
      end

      context "without a current app config" do
        let(:current) { nil }

        it "returns false" do
          expect(config.use_digest_image_ref?).to be(false)
        end
      end
    end
  end
end
