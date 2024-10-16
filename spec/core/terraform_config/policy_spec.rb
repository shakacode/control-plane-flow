# frozen_string_literal: true

require "spec_helper"

describe TerraformConfig::Policy do
  let(:config) { described_class.new(**base_options.merge(extra_options)) }

  describe "#to_tf" do
    subject(:generated) { config.to_tf }

    let(:base_options) do
      {
        name: "policy-name",
        description: "policy description",
        tags: { "tag1" => "true", "tag2" => "false" },
        target_links: ["secret/postgres-poc-credentials", "secret/postgres-poc-entrypoint-script"],
        bindings: [
          {
            "permissions" => %w[view],
            "principalLinks" => [
              "user/fake-user@fake-email.com",
              "serviceaccount/FAKE_SERVICE_ACCOUNT_NAME",
              "group/FAKE-GROUP"
            ]
          },
          {
            "permissions" => %w[view edit],
            "principalLinks" => ["user/fake-admin-user@fake-email.com"]
          }
        ]
      }
    end

    let(:extra_options) { {} }

    context "with target query" do
      let(:extra_options) do
        {
          target_kind: "agent",
          target_query: {
            "kind" => "agent",
            "fetch" => fetch_type,
            "spec" => {
              "match" => match_type,
              "terms" => [
                {
                  "op" => "=",
                  "tag" => "tag_name",
                  "value" => "some_tag"
                }
              ]
            }
          }
        }
      end

      let(:fetch_type) { "items" }
      let(:match_type) { "all" }

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            resource "cpln_policy" "policy-name" {
              name = "policy-name"
              description = "policy description"
              tags = {
                tag1 = "true"
                tag2 = "false"
              }
              target_kind = "agent"
              target_links = ["secret/postgres-poc-credentials", "secret/postgres-poc-entrypoint-script"]
              binding {
                permissions = ["view"]
                principal_links = ["user/fake-user@fake-email.com", "serviceaccount/FAKE_SERVICE_ACCOUNT_NAME", "group/FAKE-GROUP"]
              }
              binding {
                permissions = ["view", "edit"]
                principal_links = ["user/fake-admin-user@fake-email.com"]
              }
              target_query {
                fetch = "items"
                spec {
                  match = "all"
                  terms {
                    op = "="
                    tag = "tag_name"
                    value = "some_tag"
                  }
                }
              }
            }
          EXPECTED
        )
      end

      context "when fetch type is invalid" do
        let(:fetch_type) { "invalid" }

        it "raises an argument error" do
          expect { generated }.to raise_error(
            ArgumentError,
            "Invalid fetch type - #{fetch_type}. Should be either `links` or `items`"
          )
        end
      end

      context "when match type is invalid" do
        let(:match_type) { "invalid" }

        it "raises an argument error" do
          expect { generated }.to raise_error(
            ArgumentError,
            "Invalid match type - #{match_type}. Should be either `all`, `any` or `none`"
          )
        end
      end

      context "when term is invalid" do
        let(:extra_options) do
          {
            target_query: {
              "spec" => {
                "terms" => [
                  {
                    "property" => "id", # extra attribute
                    "tag" => "tag_name"
                  }
                ]
              }
            }
          }
        end

        it "raises an argument error" do
          expect { generated }.to raise_error(
            ArgumentError,
            "`target_query.spec.terms` can contain only one of the following attributes: `property`, `rel`, `tag`."
          )
        end
      end
    end

    context "without target query" do
      let(:extra_options) { {} }

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            resource "cpln_policy" "policy-name" {
              name = "policy-name"
              description = "policy description"
              tags = {
                tag1 = "true"
                tag2 = "false"
              }
              target_links = ["secret/postgres-poc-credentials", "secret/postgres-poc-entrypoint-script"]
              binding {
                permissions = ["view"]
                principal_links = ["user/fake-user@fake-email.com", "serviceaccount/FAKE_SERVICE_ACCOUNT_NAME", "group/FAKE-GROUP"]
              }
              binding {
                permissions = ["view", "edit"]
                principal_links = ["user/fake-admin-user@fake-email.com"]
              }
            }
          EXPECTED
        )
      end
    end

    context "when gvc is required" do
      let(:extra_options) { { target_kind: "identity", gvc: nil } }

      it "raises error if gvc is missing" do
        expect { generated }.to raise_error(ArgumentError, "`gvc` is required for `identity` target kind")
      end
    end
  end
end
