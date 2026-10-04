# frozen_string_literal: true

require "spec_helper"

describe DisposablePostgresHelpers do # rubocop:disable RSpec/MultipleMemoizedHelpers
  let(:app) { "demo-review-pr-501" }
  let(:config) do
    instance_double(Config, app: app, org: "test-org", identity: "#{app}-identity",
                            disposable_review_secret_resource_names: ["#{app}-secrets", "#{app}-secrets-policy"],
                            shared_secret_grants: [], options: { yes: true })
  end
  let(:cp) { instance_double(Controlplane) }
  let(:helpers) { described_class.new(config, cp) }
  let(:tag) { { "cpflow-disposable-postgres-app" => app } }
  let(:secret) { { "kind" => "secret", "name" => "#{app}-pg", "type" => "dictionary", "tags" => tag } }
  let(:script) { { "kind" => "secret", "name" => "#{app}-pg-script", "type" => "opaque", "tags" => tag } }
  let(:policy) do
    { "kind" => "policy", "name" => "#{app}-pg-access", "tags" => tag,
      "targetKind" => "secret", "targetLinks" => ["//secret/#{app}-pg", "//secret/#{app}-pg-script"],
      "bindings" => [{ "permissions" => ["reveal"], "principalLinks" =>
        ["//gvc/#{app}/identity/#{app}-pg-identity", "/org/test-org/gvc/#{app}/identity/#{app}-identity"] }] }
  end

  before do
    allow(cp).to receive(:fetch_secret).with("#{app}-pg").and_return(secret)
    allow(cp).to receive(:fetch_secret).with("#{app}-pg-script").and_return(script)
    allow(cp).to receive(:fetch_policy).with("#{app}-pg-access").and_return(policy)
    allow(cp).to receive_messages(delete_secret: true, delete_policy: true, fetch_policies: { "items" => [] })
  end

  it "removes marked helpers and their exact policy" do
    helpers.delete { |_kind, _name, &operation| operation.call }
    expect(cp).to have_received(:delete_secret).with("#{app}-pg")
    expect(cp).to have_received(:delete_secret).with("#{app}-pg-script")
    expect(cp).to have_received(:delete_policy).with("#{app}-pg-access")
  end

  it "preserves unmarked legacy helpers" do
    [secret, script, policy].each { |resource| resource.delete("tags") }
    helpers.delete { |_kind, _name, &operation| operation.call }
    expect(cp).not_to have_received(:delete_secret)
    expect(cp).not_to have_received(:delete_policy)
  end

  it "refuses mixed ownership before removing anything" do
    script["tags"] = { "cpflow-disposable-postgres-app" => "another-app" }
    expect { helpers.delete }.to raise_error(/ownership/)
    expect(cp).not_to have_received(:delete_secret)
    expect(cp).not_to have_received(:delete_policy)
  end

  it "refuses additional policy targets" do
    policy["targetLinks"] << "//secret/shared"
    expect { helpers.validate! }.to raise_error(/ownership/)
  end

  it "refuses foreign principals and permissions" do
    policy["bindings"].first["principalLinks"] << "/org/other/gvc/#{app}/identity/#{app}-identity"
    expect { helpers.validate! }.to raise_error(/ownership/)
    policy["bindings"].first["principalLinks"].pop
    policy["bindings"].first["permissions"] << "manage"
    expect { helpers.validate! }.to raise_error(/ownership/)
  end

  it "refuses alternative policy selectors" do
    policy["targetQuery"] = {}
    expect { helpers.validate! }.to raise_error(/ownership/)
  end

  it "refuses a helper explicitly configured as shared" do
    allow(config).to receive(:shared_secret_grants).and_return([{ secret_name: "#{app}-pg", policy_name: "shared" }])
    expect { helpers.validate! }.to raise_error(/ownership/)
  end

  it "finishes partial cleanup after the policy and one secret are absent" do
    allow(cp).to receive(:fetch_policy).and_return(nil)
    allow(cp).to receive(:fetch_secret).with("#{app}-pg").and_return(nil)
    helpers.delete { |_kind, _name, &operation| operation.call }
    expect(cp).to have_received(:delete_secret).with("#{app}-pg-script")
    expect(cp).not_to have_received(:delete_policy)
  end

  it "retries after a secret deletion fails" do
    allow(cp).to receive(:delete_policy) { allow(cp).to receive(:fetch_policy).and_return(nil) }
    allow(cp).to receive(:delete_secret).with("#{app}-pg").and_raise("interrupted")
    expect { helpers.delete { |_kind, _name, &operation| operation.call } }.to raise_error("interrupted")
    allow(cp).to receive(:delete_secret).with("#{app}-pg").and_return(true)
    helpers.delete { |_kind, _name, &operation| operation.call }
    expect(cp).to have_received(:delete_secret).with("#{app}-pg-script")
  end

  it "never adopts an existing unmarked resource on template application" do
    secret.delete("tags")
    template = script.merge("name" => "#{app}-pg", "type" => "dictionary")
    expect { helpers.prepare_templates!([template]) }.to raise_error(/ownership/)
  end

  it "validates template targets before ownership can be asserted" do
    policy["targetLinks"] << "//secret/shared"
    expect { helpers.prepare_templates!([policy]) }.to raise_error(/ownership/)
  end

  it "does not mark persistent apps as disposable" do
    allow(config).to receive(:disposable_review_secret_resource_names).and_return(nil)
    helpers.prepare_templates!([secret, script, policy])
    expect(secret["tags"]).to be_empty
    expect { helpers.delete }.not_to raise_error
    expect(cp).not_to have_received(:delete_secret)
  end

  it "cleans PostgreSQL helpers through delete when the GVC is absent" do
    command = Command::Delete.new(config)
    allow(cp).to receive(:fetch_gvc).and_return(nil)
    allow(command).to receive_messages(cp: cp, validate_disposable_review_secret_resources!: :none)
    allow(command).to receive(:delete_generated_review_secret_resources)
    command.call
    expect(cp).to have_received(:delete_policy).with("#{app}-pg-access")
    expect(cp).to have_received(:delete_secret).with("#{app}-pg-script")
  end

  it "refuses unsafe helpers before touching live app data" do
    command = Command::Delete.new(config)
    allow(command).to receive(:cp).and_return(cp)
    allow(cp).to receive(:fetch_gvc).and_return({ "name" => app })
    allow(command).to receive(:delete_volumesets)
    policy["bindings"].first["principalLinks"] << "//user/foreign"
    expect { command.call }.to raise_error(/ownership/)
    expect(command).not_to have_received(:delete_volumesets)
  end

  it "does not adopt unmarked secrets when only a policy template is supplied" do
    secret.delete("tags")
    allow(cp).to receive(:fetch_policy).and_return(nil)
    expect { helpers.prepare_templates!([policy]) }.to raise_error(/ownership/)
  end

  it "permits only the expected secret types" do
    script["type"] = "dictionary"
    expect { helpers.validate! }.to raise_error(/ownership/)
  end

  it "accepts fully qualified targets and empty bindings after partial cleanup" do
    policy["targetLinks"] = ["/org/test-org/secret/#{app}-pg-script", "/org/test-org/secret/#{app}-pg"]
    policy["bindings"] = []
    expect(helpers.validate!.size).to eq(3)
  end

  it "refuses malformed bindings, duplicate targets and foreign organization targets" do
    policy["bindings"] = nil
    expect { helpers.validate! }.to raise_error(/ownership/)
    policy["bindings"] = []
    policy["targetLinks"] = ["//secret/#{app}-pg", "//secret/#{app}-pg"]
    expect { helpers.validate! }.to raise_error(/ownership/)
    policy["targetLinks"] = ["/org/foreign/secret/#{app}-pg", "//secret/#{app}-pg-script"]
    expect { helpers.validate! }.to raise_error(/ownership/)
  end

  it "preserves all resources for persistent app cleanup" do
    allow(config).to receive(:disposable_review_secret_resource_names).and_return(nil)
    helpers.delete
    expect(cp).not_to have_received(:delete_policy)
    expect(cp).not_to have_received(:delete_secret)
  end

  it "does not read unrelated resources for unmarked templates" do
    secret.delete("tags")
    helpers.prepare_templates!([secret])
    expect(cp).not_to have_received(:fetch_policy)
  end

  it "refuses helpers shared by a policy outside the app configuration" do
    allow(cp).to receive(:fetch_policies).and_return(
      { "items" => [{ "name" => "foreign", "targetKind" => "secret", "targetLinks" => ["//secret/#{app}-pg"] }] }
    )
    expect { helpers.validate! }.to raise_error(/ownership/)
  end

  it "refuses ambiguous secret policy queries" do
    allow(cp).to receive(:fetch_policies).and_return(
      { "items" => [{ "name" => "foreign", "targetKind" => "secret", "targetQuery" => {} }] }
    )
    expect { helpers.validate! }.to raise_error(/ownership/)
  end

  it "fails closed when policy inventory is unavailable" do
    allow(cp).to receive(:fetch_policies).and_raise("provider unavailable")
    expect { helpers.delete }.to raise_error("provider unavailable")
    expect(cp).not_to have_received(:delete_secret)
  end

  it "rejects partially tagged helper templates before creation" do
    policy.delete("tags")
    [secret, script, policy].each do |resource|
      allow(cp).to receive(resource["kind"] == "policy" ? :fetch_policy : :fetch_secret)
        .with(resource["name"]).and_return(nil)
    end
    expect { helpers.prepare_templates!([secret, script, policy]) }.to raise_error(/ownership/)
  end

  it "allows org-wide metadata administration without treating helpers as shared credentials" do
    allow(cp).to receive(:fetch_policies).and_return(
      { "items" => [{ "name" => "admins", "targetKind" => "secret", "target" => "all",
                      "bindings" => [{ "permissions" => ["manage"], "principalLinks" => ["//group/admins"] }] }] }
    )
    expect(helpers.validate!.size).to eq(3)
  end

  it "still refuses broad policies granting credential access" do
    allow(cp).to receive(:fetch_policies).and_return(
      { "items" => [{ "name" => "consumers", "targetKind" => "secret", "target" => "all",
                      "bindings" => [{ "permissions" => ["reveal"], "principalLinks" => ["//group/consumers"] }] }] }
    )
    expect { helpers.validate! }.to raise_error(/ownership/)
  end

  it "ignores policies with no targets or selectors" do
    allow(cp).to receive(:fetch_policies).and_return(
      { "items" => [{ "name" => "empty", "targetKind" => "secret", "targetLinks" => [] }] }
    )
    expect(helpers.validate!.size).to eq(3)
  end
end
