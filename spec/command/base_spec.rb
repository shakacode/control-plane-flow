# frozen_string_literal: true

require "spec_helper"

describe Command::Base do
  let(:config) { instance_double(Command::Config) }
  let(:command) { described_class.new(config) }

  around do |example|
    suppress_output { example.run }
  end

  describe "#step" do
    let(:message) { "test message" }
    let(:common_options) { { abort_on_error: false } }

    context "with retry_on_failure: true" do
      let(:options) { common_options.merge(retry_on_failure: true, wait: 0) }

      it "retries block until success" do
        run_count = 0

        command.step(message, **options) do
          run_count += 1
          true if run_count == 3
        end

        expect(run_count).to eq(3)
      end

      it "does not exceed default max_retry_count" do
        run_count = 0

        command.step(message, **options) do
          run_count += 1
          false
        end

        expect(run_count).to eq(1001)
      end

      context "with max_retry_count option" do # rubocop:disable RSpec/MultipleMemoizedHelpers
        let(:options_with_max_retry_count) { common_options.merge(retry_on_failure: true, wait: 0, max_retry_count: 1) }

        it "retries block specified times" do
          run_count = 0

          command.step(message, **options_with_max_retry_count) do
            run_count += 1
            false
          end

          expect(run_count).to eq(2)
        end
      end
    end

    context "with retry_on_failure: false" do
      let(:options) { common_options.merge(retry_on_failure: false) }

      it "does not retry block" do
        run_count = 0

        command.step(message, **options) do
          run_count += 1
          false
        end

        expect(run_count).to eq(1)
      end
    end
  end

  describe "#resolve_shared_secret_policy_grants" do
    let(:config) do
      instance_double(
        Config,
        org: "test-org",
        identity_link: "/org/test-org/gvc/test-app/identity/test-app-identity",
        shared_secret_grants: [
          {
            name: "database",
            secret_name: "shared-database-secrets",
            policy_name: "shared-database-secrets-policy"
          }
        ]
      )
    end
    let(:cp) { instance_double(Controlplane) }
    let(:policy) do
      {
        "targetKind" => "secret",
        "targetLinks" => ["//secret/shared-database-secrets"],
        "bindings" => []
      }
    end

    before do
      allow(command).to receive(:cp).and_return(cp)
      allow(cp).to receive(:fetch_policy).with("shared-database-secrets-policy").and_return(policy)
    end

    it "keeps the diagnostic placeholder aligned with the generated Postgres template" do
      template_path = File.expand_path("../../lib/generator_templates/templates/postgres.yml", __dir__)
      generated_secret = YAML.load_stream(File.read(template_path)).find { |item| item&.fetch("kind", nil) == "secret" }

      expect(generated_secret.dig("data", "password")).to eq(
        described_class::GENERATED_POSTGRES_PASSWORD_PLACEHOLDER
      )
    end

    it "warns when the shared secret still has the generated Postgres password placeholder" do
      allow(cp).to receive(:reveal_secret)
        .with("shared-database-secrets")
        .and_return(
          "data" => {
            "password" => "the_password",
            "api_token" => "private-token-sentinel"
          }
        )
      allow(Shell).to receive(:warn)

      command.resolve_shared_secret_policy_grants

      expect(Shell).to have_received(:warn).with(
        "Shared secret grant 'database' targets secret 'shared-database-secrets', whose password is still the " \
        "generated placeholder. Review apps will fail authentication until it is replaced."
      )
      expect(Shell).not_to have_received(:warn).with(/the_password/)
      expect(Shell).not_to have_received(:warn).with(/private-token-sentinel/)
    end

    it "does not warn for a non-placeholder password" do
      allow(cp).to receive(:reveal_secret)
        .with("shared-database-secrets")
        .and_return("data" => { "password" => "a-real-password-sentinel" })
      allow(Shell).to receive(:warn)

      command.resolve_shared_secret_policy_grants

      expect(Shell).not_to have_received(:warn)
    end

    it "does not block the command when the current token cannot reveal the secret" do
      response = instance_double(Net::HTTPForbidden, to_s: "403 Forbidden")
      error = ControlplaneApiDirect::ForbiddenError.new(
        url: "/org/test-org/secret/shared-database-secrets/-reveal",
        response: response
      )
      allow(cp).to receive(:reveal_secret).with("shared-database-secrets").and_raise(error)
      allow(Shell).to receive(:warn)

      expect { command.resolve_shared_secret_policy_grants }.not_to raise_error
      expect(Shell).not_to have_received(:warn)
    end

    it "does not block the command when the optional reveal diagnostic fails" do
      allow(cp).to receive(:reveal_secret)
        .with("shared-database-secrets")
        .and_raise("temporary reveal failure")
      allow(Shell).to receive(:warn)

      expect { command.resolve_shared_secret_policy_grants }.not_to raise_error
      expect(Shell).not_to have_received(:warn)
    end
  end
end
