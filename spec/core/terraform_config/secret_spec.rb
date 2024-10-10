# frozen_string_literal: true

require "spec_helper"

describe TerraformConfig::Secret do
  let(:config) { described_class.new(**base_options.merge(type: type, data: data)) }

  let(:base_options) do
    {
      name: "some-secret",
      description: "secret description",
      tags: { "tag1" => "some-tag-1", "tag2" => "some-tag-2" }
    }
  end

  describe "#to_tf" do
    subject(:generated) { config.to_tf }

    context "with aws secret type" do
      let(:type) { "aws" }
      let(:data) do
        {
          "accessKey" => "FAKE_AWS_ACCESS_KEY",
          "secretKey" => "FAKE_AWS_SECRET_KEY",
          "roleArn" => "arn:awskey",
          "externalId" => "123"
        }
      end

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            resource "cpln_secret" "#{base_options.fetch(:name)}" {
              name = "#{base_options.fetch(:name)}"
              description = "#{base_options.fetch(:description)}"
              tags = {
                tag1 = "some-tag-1"
                tag2 = "some-tag-2"
              }
              aws {
                secret_key = "#{data.fetch('secretKey')}"
                access_key = "#{data.fetch('accessKey')}"
                role_arn = "#{data.fetch('roleArn')}"
                external_id = "#{data.fetch('externalId')}"
              }
            }
          EXPECTED
        )
      end
    end

    context "with azure-connector secret type" do
      let(:type) { "azure-connector" }
      let(:data) do
        {
          "url" => "https://azure-connector-url.com",
          "code" => "123"
        }
      end

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            resource "cpln_secret" "#{base_options.fetch(:name)}" {
              name = "#{base_options.fetch(:name)}"
              description = "#{base_options.fetch(:description)}"
              tags = {
                tag1 = "some-tag-1"
                tag2 = "some-tag-2"
              }
              azure_connector {
                url = "#{data.fetch('url')}"
                code = "#{data.fetch('code')}"
              }
            }
          EXPECTED
        )
      end
    end

    context "with azure-sdk secret type" do
      let(:type) { "azure-sdk" }
      let(:data) do
        {
          subscriptionId: "2cd2674e-4f89-4a1f-b420-7a1361b46ef7",
          tenantId: "292f5674-78b0-488b-9ff8-6d30d77f38d9",
          clientId: "649746ce-d862-49d5-a5eb-7d5aad90f54e",
          clientSecret: "FAKE_CLIENT_SECRET"
        }.to_json
      end

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            resource "cpln_secret" "#{base_options.fetch(:name)}" {
              name = "#{base_options.fetch(:name)}"
              description = "#{base_options.fetch(:description)}"
              tags = {
                tag1 = "some-tag-1"
                tag2 = "some-tag-2"
              }
              azure_sdk = "#{data}"
            }
          EXPECTED
        )
      end
    end

    context "with dictionary secret type" do
      let(:type) { "dictionary" }
      let(:data) do
        {
          "key1" => "value1",
          "key2" => "value2"
        }
      end

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            resource "cpln_secret" "#{base_options.fetch(:name)}" {
              name = "#{base_options.fetch(:name)}"
              description = "#{base_options.fetch(:description)}"
              tags = {
                tag1 = "some-tag-1"
                tag2 = "some-tag-2"
              }
              dictionary = {
                key1 = "value1"
                key2 = "value2"
              }
            }
          EXPECTED
        )
      end
    end

    context "with docker secret type" do
      let(:type) { "docker" }
      let(:data) do
        {
          auths: {
            "registry-server": {
              username: "username",
              password: "password",
              email: "email",
              auth: "FAKE_AUTH"
            }
          }
        }.to_json
      end

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            resource "cpln_secret" "#{base_options.fetch(:name)}" {
              name = "#{base_options.fetch(:name)}"
              description = "#{base_options.fetch(:description)}"
              tags = {
                tag1 = "some-tag-1"
                tag2 = "some-tag-2"
              }
              docker = "#{data}"
            }
          EXPECTED
        )
      end
    end

    context "with ecr secret type" do
      let(:type) { "ecr" }
      let(:data) do
        {
          "accessKey" => "FAKE_ECR_ACCESS_KEY",
          "secretKey" => "FAKE_ECR_SECRET_KEY",
          "repos" => ["015716931765.dkr.ecr.us-west-2.amazonaws.com/cpln-test"],
          "roleArn" => "arn:awskey",
          "externalId" => "123"
        }
      end

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            resource "cpln_secret" "#{base_options.fetch(:name)}" {
              name = "#{base_options.fetch(:name)}"
              description = "#{base_options.fetch(:description)}"
              tags = {
                tag1 = "some-tag-1"
                tag2 = "some-tag-2"
              }
              ecr {
                secret_key = "#{data.fetch('secretKey')}"
                access_key = "#{data.fetch('accessKey')}"
                repos = #{data.fetch('repos')}
                role_arn = "#{data.fetch('roleArn')}"
                external_id = "#{data.fetch('externalId')}"
              }
            }
          EXPECTED
        )
      end
    end

    context "with gcp secret type" do
      let(:type) { "gcp" }
      let(:data) do
        {
          "type" => "gcp",
          "project_id" => "cpln12345",
          "private_key_id" => "pvt_key",
          "private_key" => "key",
          "client_email" => "support@cpln.io",
          "client_id" => "12744",
          "auth_uri" => "cloud.google.com",
          "token_uri" => "token.cloud.google.com",
          "auth_provider_x509_cert_url" => "cert.google.com",
          "client_x509_cert_url" => "cert.google.com"
        }.to_json
      end

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            resource "cpln_secret" "#{base_options.fetch(:name)}" {
              name = "#{base_options.fetch(:name)}"
              description = "#{base_options.fetch(:description)}"
              tags = {
                tag1 = "some-tag-1"
                tag2 = "some-tag-2"
              }
              gcp = "#{data}"
            }
          EXPECTED
        )
      end
    end

    context "with keypair secret type" do
      let(:type) { "keypair" }
      let(:data) do
        {
          "secretKey" => "<<\nPRIVATE\n_KEY\n_CONTENT\n>>",
          "publicKey" => "<<\nPUBLIC\n_KEY\n_CONTENT\n>>",
          "passphrase" => "cpln"
        }
      end

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            resource "cpln_secret" "#{base_options.fetch(:name)}" {
              name = "#{base_options.fetch(:name)}"
              description = "#{base_options.fetch(:description)}"
              tags = {
                tag1 = "some-tag-1"
                tag2 = "some-tag-2"
              }
              keypair {
                secret_key = EOF
                  <<
                  PRIVATE
                  _KEY
                  _CONTENT
                  >>
                EOF
                public_key = EOF
                  <<
                  PUBLIC
                  _KEY
                  _CONTENT
                  >>
                EOF
                passphrase = "#{data.fetch('passphrase')}"
              }
            }
          EXPECTED
        )
      end
    end

    context "with nats-account secret type" do
      let(:type) { "nats-account" }
      let(:data) do
        {
          "accountId" => "FAKE_ACCOUNT_ID",
          "privateKey" => "FAKE_PRIVATE_KEY"
        }
      end

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            resource "cpln_secret" "#{base_options.fetch(:name)}" {
              name = "#{base_options.fetch(:name)}"
              description = "#{base_options.fetch(:description)}"
              tags = {
                tag1 = "some-tag-1"
                tag2 = "some-tag-2"
              }
              nats_account {
                account_id = "#{data.fetch('accountId')}"
                private_key = "#{data.fetch('privateKey')}"
              }
            }
          EXPECTED
        )
      end
    end

    context "with opaque secret type" do
      let(:type) { "opaque" }
      let(:data) do
        {
          "payload" => "payload",
          "encoding" => "plain"
        }
      end

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            resource "cpln_secret" "#{base_options.fetch(:name)}" {
              name = "#{base_options.fetch(:name)}"
              description = "#{base_options.fetch(:description)}"
              tags = {
                tag1 = "some-tag-1"
                tag2 = "some-tag-2"
              }
              opaque {
                payload = "#{data.fetch('payload')}"
                encoding = "#{data.fetch('encoding')}"
              }
            }
          EXPECTED
        )
      end
    end

    context "with tls secret type" do
      let(:type) { "tls" }
      let(:data) do
        {
          "key" => "<<\nPRIVATE\n_KEY\n_CONTENT\n>>",
          "cert" => "<<\nCERTIFICATE\n_CONTENT\n>>",
          "chain" => "None. The above key and certificate were self-signed."
        }
      end

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            resource "cpln_secret" "#{base_options.fetch(:name)}" {
              name = "#{base_options.fetch(:name)}"
              description = "#{base_options.fetch(:description)}"
              tags = {
                tag1 = "some-tag-1"
                tag2 = "some-tag-2"
              }
              tls {
                key = EOF
                  <<
                  PRIVATE
                  _KEY
                  _CONTENT
                  >>
                EOF
                cert = EOF
                  <<
                  CERTIFICATE
                  _CONTENT
                  >>
                EOF
                chain = "#{data.fetch('chain')}"
              }
            }
          EXPECTED
        )
      end
    end

    context "with userpass secret type" do
      let(:type) { "userpass" }
      let(:data) do
        {
          "username" => "cpln_username",
          "password" => "cpln_password",
          "encoding" => "base64"
        }
      end

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            resource "cpln_secret" "#{base_options.fetch(:name)}" {
              name = "#{base_options.fetch(:name)}"
              description = "#{base_options.fetch(:description)}"
              tags = {
                tag1 = "some-tag-1"
                tag2 = "some-tag-2"
              }
              userpass {
                username = "#{data.fetch('username')}"
                password = "#{data.fetch('password')}"
                encoding = "#{data.fetch('encoding')}"
              }
            }
          EXPECTED
        )
      end
    end
  end
end
