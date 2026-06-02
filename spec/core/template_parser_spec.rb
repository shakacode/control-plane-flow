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
        image_link: "/org/test-org/image/test-review-123:1",
        identity: "test-review-123-identity",
        identity_link: "/org/test-org/gvc/test-review-123/identity/test-review-123-identity",
        secrets: "test-review-secrets",
        secrets_policy: "test-review-secrets-policy",
        shared_secret_placeholders: {
          "{{SHARED_SECRET_DATABASE}}" => "test-shared-database-secrets"
        }
      )
    end
    let(:cp) { instance_double(Controlplane, latest_image: "test-review-123:1") }
    let(:command) { instance_double(Command::ApplyTemplate, config: config, cp: cp) }
    let(:parser) { described_class.new(command) }
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
  end
end
