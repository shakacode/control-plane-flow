# frozen_string_literal: true

require "spec_helper"

describe TerraformConfig::Generator do
  let(:generator) { described_class.new(config: config, template: template) }

  let(:config) { instance_double(Config, org: "org-name", app: "app-name") }

  context "when template's kind is unsupported" do
    let(:template) { { "kind" => "invalid" } }

    it "raises an error when unsupported template kind is used", :aggregate_failures do
      expect { generator }.to raise_error(ArgumentError, "Unsupported template kind: #{template['kind']}")
    end
  end

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

    it "generates correct terraform configs", :aggregate_failures do
      expected_filename = "gvc.tf"

      tf_configs = generator.tf_configs
      expect(tf_configs.count).to eq(1)

      filenames = tf_configs.keys
      expect(filenames).to contain_exactly(expected_filename)

      tf_config = tf_configs[expected_filename]
      expect(tf_config).to be_an_instance_of(TerraformConfig::Gvc)

      expect(tf_config.name).to eq(config.app)
      expect(tf_config.description).to eq("description")
      expect(tf_config.tags).to eq(tag1: "tag1_value", tag2: "tag2_value")

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

    it "generates correct terraform configs", :aggregate_failures do
      expected_filename = "identities.tf"

      tf_configs = generator.tf_configs
      expect(tf_configs.count).to eq(1)

      filenames = tf_configs.keys
      expect(filenames).to contain_exactly(expected_filename)

      tf_config = tf_configs[expected_filename]
      expect(tf_config).to be_an_instance_of(TerraformConfig::Identity)

      expect(tf_config.name).to eq("identity-name")
      expect(tf_config.description).to eq("description")
      expect(tf_config.tags).to eq(tag1: "tag1_value", tag2: "tag2_value")
    end
  end

  context "when template's kind is secret" do
    let(:template) do
      {
        "kind" => "secret",
        "type" => "dictionary",
        "name" => "secret-name",
        "description" => "description",
        "tags" => { "tag1" => "tag1_value", "tag2" => "tag2_value" },
        "data" => { "key1" => "key1_value", "key2" => "key2_value2" }
      }
    end

    it "generates correct terraform config and filename for it", :aggregate_failures do
      expected_filename = "secrets.tf"

      tf_configs = generator.tf_configs
      expect(tf_configs.count).to eq(1)

      filenames = tf_configs.keys
      expect(filenames).to contain_exactly(expected_filename)

      tf_config = tf_configs[expected_filename]
      expect(tf_config).to be_an_instance_of(TerraformConfig::Secret)

      expect(tf_config.name).to eq("secret-name")
      expect(tf_config.description).to eq("description")
      expect(tf_config.tags).to eq(tag1: "tag1_value", tag2: "tag2_value")
    end
  end

  context "when template's kind is policy" do
    let(:template) do
      {
        "kind" => "policy",
        "name" => "policy-name",
        "description" => "policy description",
        "tags" => { "tag1" => "tag1_value", "tag2" => "tag2_value" },
        "target" => "all",
        "targetKind" => "secret",
        "targetLinks" => [
          "//secret/postgres-poc-credentials",
          "//secret/postgres-poc-entrypoint-script"
        ],
        "bindings" => [
          {
            "permissions" => %w[reveal view use],
            "principalLinks" => %W[//gvc/#{config.app}/identity/postgres-poc-identity]
          },
          {
            "permissions" => %w[view],
            "principalLinks" => %w[user/fake-user@fake-email.com]
          }
        ]
      }
    end

    it "generates correct terraform configs", :aggregate_failures do
      expected_filename = "policies.tf"

      tf_configs = generator.tf_configs
      expect(tf_configs.count).to eq(1)

      filenames = tf_configs.keys
      expect(filenames).to contain_exactly(expected_filename)

      tf_config = tf_configs[expected_filename]
      expect(tf_config).to be_an_instance_of(TerraformConfig::Policy)

      expect(tf_config.name).to eq("policy-name")
      expect(tf_config.description).to eq("policy description")
      expect(tf_config.tags).to eq(tag1: "tag1_value", tag2: "tag2_value")
      expect(tf_config.target).to eq("all")
      expect(tf_config.target_kind).to eq("secret")
      expect(tf_config.target_links).to eq(%w[postgres-poc-credentials postgres-poc-entrypoint-script])
      expect(tf_config.bindings).to contain_exactly(
        {
          permissions: %w[reveal view use],
          principal_links: %W[gvc/#{config.app}/identity/postgres-poc-identity]
        },
        {
          permissions: %w[view],
          principal_links: %w[user/fake-user@fake-email.com]
        }
      )
    end
  end

  context "when template's kind is volumeset" do
    let(:template) do
      {
        "kind" => "volumeset",
        "name" => "volume-set-name",
        "description" => "volume set description",
        "tags" => { "tag1" => "tag1_value", "tag2" => "tag2_value" },
        "spec" => {
          "initialCapacity" => 20,
          "performanceClass" => "general-purpose-ssd",
          "fileSystemType" => "xfs",
          "storageClassSuffix" => "suffix",
          "snapshots" => {
            "createFinalSnapshot" => true,
            "retentionDuration" => "7d",
            "schedule" => "0 1 * * *"
          },
          "autoscaling" => {
            "maxCapacity" => 100,
            "minFreePercentage" => 20,
            "scalingFactor" => 1.5
          }
        }
      }
    end

    it "generates correct terraform config and filename for it", :aggregate_failures do
      expected_filename = "volumesets.tf"

      tf_configs = generator.tf_configs
      expect(tf_configs.count).to eq(1)

      filenames = tf_configs.keys
      expect(filenames).to contain_exactly(expected_filename)

      tf_config = tf_configs[expected_filename]
      expect(tf_config).to be_an_instance_of(TerraformConfig::VolumeSet)

      expect(tf_config.name).to eq("volume-set-name")
      expect(tf_config.description).to eq("volume set description")
      expect(tf_config.tags).to eq(tag1: "tag1_value", tag2: "tag2_value")
      expect(tf_config.initial_capacity).to eq(20)
      expect(tf_config.performance_class).to eq("general-purpose-ssd")
      expect(tf_config.file_system_type).to eq("xfs")
      expect(tf_config.storage_class_suffix).to eq("suffix")
      expect(tf_config.snapshots).to eq(
        create_final_snapshot: true,
        retention_duration: "7d",
        schedule: "0 1 * * *"
      )
      expect(tf_config.autoscaling).to eq(
        max_capacity: 100,
        min_free_percentage: 20,
        scaling_factor: 1.5
      )
    end
  end

  context "when template's kind is auditctx" do
    let(:template) do
      {
        "kind" => "auditctx",
        "name" => "audit-context-name",
        "description" => "audit context description",
        "tags" => { "tag1" => "tag1_value", "tag2" => "tag2_value" }
      }
    end

    it "generates correct terraform config and filename for it", :aggregate_failures do
      expected_filename = "audit_contexts.tf"

      tf_configs = generator.tf_configs
      expect(tf_configs.count).to eq(1)

      filenames = tf_configs.keys
      expect(filenames).to contain_exactly(expected_filename)

      tf_config = tf_configs[expected_filename]
      expect(tf_config).to be_an_instance_of(TerraformConfig::AuditContext)

      expect(tf_config.name).to eq("audit-context-name")
      expect(tf_config.description).to eq("audit context description")
      expect(tf_config.tags).to eq(tag1: "tag1_value", tag2: "tag2_value")
    end
  end

  context "when template's kind is workload" do
    let(:template) do
      {
        "kind" => "workload",
        "name" => "main",
        "description" => "main workload description",
        "tags" => {
          "tag1" => "tag1_value",
          "tag2" => "tag2_value"
        },
        "spec" => {
          "type" => "standard",
          "containers" => [
            {
              "name" => "rails",
              "cpu" => "500m",
              "env" => [
                { "name" => "RACK_ENV", "value" => "production" },
                { "name" => "RAILS_ENV", "value" => "production" },
                { "name" => "SECRET_KEY_BASE", "value" => "SECRET_VALUE" }
              ],
              "image" => "/org/org-name/image/rails:7",
              "inheritEnv" => false,
              "memory" => "512Mi",
              "ports" => [{ "number" => 3000, "protocol" => "http" }]
            },
            {
              "name" => "redis",
              "cpu" => "500m",
              "image" => "redis",
              "inheritEnv" => true,
              "memory" => "512Mi"
            },
            {
              "name" => "postgres",
              "args" => [
                "-c",
                "cat /usr/local/bin/cpln-entrypoint.sh >> ./cpln-entrypoint.sh && " \
                "chmod u+x ./cpln-entrypoint.sh && " \
                "./cpln-entrypoint.sh postgres"
              ],
              "command" => "/bin/bash",
              "cpu" => "500m",
              "env" => [
                { "name" => "POSTGRES_PASSWORD", "value" => "FAKE_PASSWORD" },
                { "name" => "TZ", "value" => "UTC" }
              ],
              "image" => "ubuntu/postgres:14-22.04_beta",
              "livenessProbe" => {
                "failureThreshold" => 1,
                "initialDelaySeconds" => 10,
                "periodSeconds" => 10,
                "successThreshold" => 1,
                "tcpSocket" => { "port" => 5432 },
                "timeoutSeconds" => 1
              },
              "readinessProbe" => {
                "failureThreshold" => 1,
                "initialDelaySeconds" => 10,
                "periodSeconds" => 10,
                "successThreshold" => 1,
                "tcpSocket" => { "port" => 5432 },
                "timeoutSeconds" => 1
              },
              "volumes" => [
                {
                  "path" => "/var/lib/postgresql/data",
                  "recoveryPolicy" => "retain",
                  "uri" => "cpln://volumeset/postgres-poc-vs"
                },
                {
                  "path" => "/usr/local/bin/cpln-entrypoint.sh",
                  "recoveryPolicy" => "retain",
                  "uri" => "cpln://secret/postgres-poc-entrypoint-script"
                }
              ],
              "inheritEnv" => false,
              "memory" => "512Mi"
            }
          ],
          "defaultOptions" => {
            "autoscaling" => {
              "maxConcurrency" => 0,
              "maxScale" => 1,
              "metric" => "cpu",
              "metricPercentile" => 25,
              "minScale" => 1,
              "scaleToZeroDelay" => 300,
              "target" => 95
            },
            "capacityAI" => false,
            "debug" => false,
            "suspend" => true,
            "timeoutSeconds" => 5
          },
          "localOptions" => {
            "location" => "//location/aws-us-west-2",
            "autoscaling" => {
              "maxConcurrency" => 1,
              "maxScale" => 1,
              "metric" => "disabled",
              "scaleToZeroDelay" => 100,
              "target" => 85
            },
            "capacityAI" => true,
            "debug" => true,
            "suspend" => false,
            "timeoutSeconds" => 15
          },
          "securityOptions" => {
            "filesystemGroupId" => 1
          },
          "rolloutOptions" => {
            "minReadySeconds" => 15,
            "maxUnavailableReplicas" => "10",
            "maxSurgeReplicas" => "20",
            "scalingPolicy" => "Parallel"
          },
          "firewallConfig" => {
            "external" => {
              "inboundAllowCIDR" => ["0.0.0.0/0"],
              "outboundAllowCIDR" => [],
              "outboundAllowHostname" => [],
              "outboundAllowPort" => [
                {
                  "protocol" => "tcp",
                  "number" => 80
                }
              ]
            },
            "internal" => {
              "inboundAllowType" => "same-gvc",
              "inboundAllowWorkload" => []
            }
          },
          "identityLink" => "//gvc/gvc-name/identity/identity-name",
          "supportDynamicTags" => true,
          "loadBalancer" => {
            "direct" => {
              "enabled" => true,
              "ports" => [
                {
                  "externalPort" => 8080,
                  "protocol" => "tcp",
                  "scheme" => "https",
                  "containerPort" => 443
                },
                {
                  "externalPort" => 443,
                  "protocol" => "udp",
                  "scheme" => "http"
                }
              ]
            },
            "geoLocation" => {
              "enabled" => true,
              "headers" => {
                "asn" => "asn",
                "city" => "city",
                "country" => "country",
                "region" => "region"
              }
            }
          }
        }
      }
    end

    it "generates correct terraform configs", :aggregate_failures do
      expected_filenames = %w[main.tf rails_envs.tf postgres_envs.tf]

      tf_configs = generator.tf_configs
      expect(tf_configs.count).to eq(3)

      filenames = tf_configs.keys
      expect(filenames).to match_array(expected_filenames)

      rails_envs = tf_configs["rails_envs.tf"]
      expect(rails_envs).to be_an_instance_of(TerraformConfig::LocalVariable)
      expect(rails_envs.variables).to eq(
        rails_envs: {
          "RACK_ENV" => "production",
          "RAILS_ENV" => "production",
          "SECRET_KEY_BASE" => "SECRET_VALUE"
        }
      )

      postgres_envs = tf_configs["postgres_envs.tf"]
      expect(postgres_envs).to be_an_instance_of(TerraformConfig::LocalVariable)
      expect(postgres_envs.variables).to eq(
        postgres_envs: {
          "POSTGRES_PASSWORD" => "FAKE_PASSWORD",
          "TZ" => "UTC"
        }
      )

      main_tf_config = tf_configs["main.tf"]
      expect(main_tf_config).to be_an_instance_of(TerraformConfig::Workload)
      expect(main_tf_config.name).to eq("main")
      expect(main_tf_config.description).to eq("main workload description")
      expect(main_tf_config.tags).to eq(tag1: "tag1_value", tag2: "tag2_value")

      expect(main_tf_config.support_dynamic_tags).to be(true)
      expect(main_tf_config.firewall_spec).to eq(
        external: {
          inbound_allow_cidr: ["0.0.0.0/0"],
          outbound_allow_cidr: [],
          outbound_allow_hostname: [],
          outbound_allow_port: [{ protocol: "tcp", number: 80 }]
        },
        internal: {
          inbound_allow_type: "same-gvc",
          inbound_allow_workload: []
        }
      )

      expect(main_tf_config.identity).to eq("cpln_identity.identity-name")
      expect(main_tf_config.options).to eq(
        autoscaling: {
          max_concurrency: 0,
          max_scale: 1,
          metric: "cpu",
          metric_percentile: 25,
          min_scale: 1,
          scale_to_zero_delay: 300,
          target: 95
        },
        capacity_ai: false,
        debug: false,
        suspend: true,
        timeout_seconds: 5
      )

      expect(main_tf_config.local_options).to eq(
        location: "aws-us-west-2",
        autoscaling: {
          max_concurrency: 1,
          max_scale: 1,
          metric: "disabled",
          scale_to_zero_delay: 100,
          target: 85
        },
        capacity_ai: true,
        debug: true,
        suspend: false,
        timeout_seconds: 15
      )

      expect(main_tf_config.rollout_options).to eq(
        min_ready_seconds: 15,
        max_unavailable_replicas: "10",
        max_surge_replicas: "20",
        scaling_policy: "Parallel"
      )

      expect(main_tf_config.security_options).to eq(file_system_group_id: 1)
      expect(main_tf_config.load_balancer).to eq(
        direct: {
          enabled: true,
          ports: [
            { external_port: 8080, protocol: "tcp", scheme: "https", container_port: 443 },
            { external_port: 443, protocol: "udp", scheme: "http" }
          ]
        },
        geo_location: {
          enabled: true,
          headers: {
            asn: "asn",
            city: "city",
            country: "country",
            region: "region"
          }
        }
      )

      expect(main_tf_config.job).to be_nil
    end
  end

  context "when template's kind is agent" do
    let(:template) do
      {
        "kind" => "agent",
        "name" => "agent-name",
        "description" => "agent description",
        "tags" => { "tag1" => "tag1_value", "tag2" => "tag2_value" }
      }
    end

    it "generates correct terraform config and filename for it", :aggregate_failures do
      expected_filename = "agents.tf"

      tf_configs = generator.tf_configs
      expect(tf_configs.count).to eq(1)

      filenames = tf_configs.keys
      expect(filenames).to contain_exactly(expected_filename)

      tf_config = tf_configs[expected_filename]
      expect(tf_config).to be_an_instance_of(TerraformConfig::Agent)

      expect(tf_config.name).to eq("agent-name")
      expect(tf_config.description).to eq("agent description")
      expect(tf_config.tags).to eq(tag1: "tag1_value", tag2: "tag2_value")
    end
  end
end
