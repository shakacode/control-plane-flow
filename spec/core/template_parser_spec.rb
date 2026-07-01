# frozen_string_literal: true

require "spec_helper"

describe TemplateParser do
  describe "#parse" do
    let(:config) do
      instance_double(
        Config,
        org: "test-org",
        app: "test-review-123",
        location: "aws-us-east-2",
        location_link: "/org/test-org/location/aws-us-east-2",
        identity: "test-review-123-identity",
        identity_link: "/org/test-org/gvc/test-review-123/identity/test-review-123-identity",
        secrets: "test-review-secrets",
        secrets_policy: "test-review-secrets-policy",
        shared_secret_placeholders: {
          "{{SHARED_SECRET_DATABASE}}" => "test-shared-database-secrets"
        }
      ).tap do |config|
        allow(config).to receive(:image_link)
          .with(latest_image)
          .and_return("/org/test-org/image/#{latest_image}")
      end
    end
    let(:latest_image) { "test-review-123:1" }
    let(:cp) { instance_double(Controlplane, latest_image: latest_image) }
    let(:parser) do
      command = instance_double(Command::ApplyTemplate, config: config, cp: cp)
      described_class.new(command)
    end
    let(:template_file) do
      Tempfile.create(["shared-secret-template", ".yml"]).tap do |file|
        file.write(<<~YAML)
          kind: workload
          name: rails
          spec:
            containers:
              - name: rails
                env:
                  - name: DATABASE_URL
                    value: cpln://secret/{{SHARED_SECRET_DATABASE}}.DATABASE_URL
        YAML
        file.rewind
      end
    end

    after do
      path = template_file.path
      template_file.close
      FileUtils.rm_f(path)
    end

    it "replaces configured shared secret placeholders" do
      parsed_template = parser.parse([template_file.path]).first

      env = parsed_template.dig("spec", "containers", 0, "env")
      expect(env).to include(
        {
          "name" => "DATABASE_URL",
          "value" => "cpln://secret/test-shared-database-secrets.DATABASE_URL"
        }
      )
    end

    it "does not fetch the latest image when templates do not use image placeholders" do
      allow(cp).to receive(:latest_image)

      parser.parse([template_file.path])

      expect(cp).not_to have_received(:latest_image)
    end

    it "does not treat APP_IMAGE_LINK as the bare APP_IMAGE legacy variable" do
      template_file.rewind
      template_file.truncate(0)
      template_file.write(<<~YAML)
        kind: workload
        name: rails
        spec:
          containers:
            - name: rails
              image: "{{APP_IMAGE_LINK}}"
      YAML
      template_file.rewind

      parsed_template = parser.parse([template_file.path]).first

      expect(parsed_template.dig("spec", "containers", 0, "image"))
        .to eq("/org/test-org/image/test-review-123:1")
      expect(parser.deprecated_variables).not_to include("APP_IMAGE")
    end

    context "when the modern image replacement contains deprecated variable text" do
      let(:latest_image) { "ghcr.io/company/APP_IMAGE-utils:v1" }

      it "does not warn about the modern placeholder" do
        template_file.rewind
        template_file.truncate(0)
        template_file.write(<<~YAML)
          kind: workload
          name: rails
          spec:
            containers:
              - name: rails
                image: "{{APP_IMAGE}}"
        YAML
        template_file.rewind

        parsed_template = parser.parse([template_file.path]).first

        expect(parsed_template.dig("spec", "containers", 0, "image")).to eq(latest_image)
        expect(parser.deprecated_variables).not_to include("APP_IMAGE")
      end
    end

    it "fetches the latest image only once when modern and legacy image variables are present" do
      template_file.rewind
      template_file.truncate(0)
      template_file.write(<<~YAML)
        kind: workload
        name: rails
        spec:
          containers:
            - name: rails
              image: "{{APP_IMAGE_LINK}}"
          env:
            - name: LEGACY_IMAGE
              value: APP_IMAGE
      YAML
      template_file.rewind

      parsed_template = parser.parse([template_file.path]).first

      expect(parsed_template.dig("spec", "containers", 0, "image"))
        .to eq("/org/test-org/image/test-review-123:1")
      expect(parsed_template.dig("spec", "env", 0, "value")).to eq("test-review-123:1")
      expect(cp).to have_received(:latest_image).once
    end
  end
end
