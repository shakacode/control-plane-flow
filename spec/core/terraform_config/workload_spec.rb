# frozen_string_literal: true

require "spec_helper"

describe TerraformConfig::Workload do
  let(:config) do
    described_class.new(
      name: "main",
      description: "main workload description",
      tags: { tag1: "tag1_value", tag2: "tag2_value" },
      gvc: "cpln_gvc.app-name.name",
      identity: "cpln_identity.identity-name",
      type: type,
      support_dynamic_tags: true,
      containers: containers,
      **extra_options
    )
  end

  let(:type) { "standard" }
  let(:containers) { [rails_container] }
  let(:extra_options) { {} }

  describe "#to_tf" do
    subject(:generated) { config.to_tf }

    context "when workload's type is standard" do
      let(:type) { "standard" }

      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            module "main" {
              source = "../workload"
              type = "standard"
              name = "main"
              gvc = cpln_gvc.app-name.name
              identity = cpln_identity.identity-name
              support_dynamic_tags = true
              containers = {
                rails: {
                  image: "/org/org-name/image/rails:7",
                  cpu: "500m",
                  memory: "512Mi",
                  inherit_env: false,
                  envs: local.rails_envs,
                  ports: [
                    {
                      number: 3000,
                      protocol: "http"
                    }
                  ]
                }
              }
            }
          EXPECTED
        )
      end

      context "with multiple containers" do
        let(:containers) { [redis_container, postgres_container] }

        it "generates configs for each container" do
          expect(generated).to include(
            <<~EXPECTED.indent(2)
              containers = {
                redis: {
                  image: "redis",
                  cpu: "500m",
                  memory: "512Mi",
                  inherit_env: true
                }
                postgres: {
                  args: [
                    "-c",
                    "cat /usr/local/bin/cpln-entrypoint.sh >> ./cpln-entrypoint.sh && chmod u+x ./cpln-entrypoint.sh && ./cpln-entrypoint.sh postgres"
                  ],
                  command: "/bin/bash",
                  image: "ubuntu/postgres:14-22.04_beta",
                  cpu: "500m",
                  memory: "512Mi",
                  inherit_env: false,
                  envs: local.postgres_envs,
                  readiness_probe: {
                    tcp_socket: {
                      port: 5432
                    },
                    failure_threshold: 1,
                    initial_delay_seconds: 10,
                    period_seconds: 10,
                    success_threshold: 1,
                    timeout_seconds: 1
                  },
                  liveness_probe: {
                    tcp_socket: {
                      port: 5432
                    },
                    failure_threshold: 1,
                    initial_delay_seconds: 10,
                    period_seconds: 10,
                    success_threshold: 1,
                    timeout_seconds: 1
                  },
                  volumes: [
                    {
                      uri: "cpln://volumeset/postgres-poc-vs",
                      path: "/var/lib/postgresql/data"
                    },
                    {
                      uri: "cpln://secret/postgres-poc-entrypoint-script",
                      path: "/usr/local/bin/cpln-entrypoint.sh"
                    }
                  ]
                }
              }
            EXPECTED
          )
        end
      end

      context "with options" do
        let(:extra_options) do
          {
            options: {
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
            }
          }
        end

        it "generates options config" do
          expect(generated).to include(
            <<~EXPECTED.indent(2)
              options = {
                autoscaling: {
                  max_concurrency: 0,
                  max_scale: 1,
                  metric: "cpu",
                  metric_percentile: 25,
                  min_scale: 1,
                  scale_to_zero_delay: 300,
                  target: 95
                }
                capacity_ai: false
                suspend: true
                timeout_seconds: 5
              }
            EXPECTED
          )
        end
      end

      context "with local options" do
        let(:extra_options) do
          {
            local_options: {
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
            }
          }
        end

        it "generates local options config" do
          expect(generated).to include(
            <<~EXPECTED.indent(2)
              local_options = {
                autoscaling: {
                  max_concurrency: 1,
                  max_scale: 1,
                  metric: "disabled",
                  scale_to_zero_delay: 100,
                  target: 85
                }
                capacity_ai: true
                suspend: false
                timeout_seconds: 15
                location: "aws-us-west-2"
              }
            EXPECTED
          )
        end
      end

      context "with rollout options" do
        let(:extra_options) do
          {
            rollout_options: {
              min_ready_seconds: 15,
              max_unavailable_replicas: "10",
              max_surge_replicas: "20",
              scaling_policy: "Parallel"
            }
          }
        end

        it "generates rollout options config" do
          expect(generated).to include(
            <<~EXPECTED.indent(2)
              rollout_options = {
                min_ready_seconds: 15
                max_unavailable_replicas: "10"
                max_surge_replicas: "20"
                scaling_policy: "Parallel"
              }
            EXPECTED
          )
        end
      end

      context "with security options" do
        let(:extra_options) do
          {
            security_options: {
              file_system_group_id: 1
            }
          }
        end

        it "generates security options config" do
          expect(generated).to include(
            <<~EXPECTED.indent(2)
              security_options = {
                file_system_group_id: 1
              }
            EXPECTED
          )
        end
      end

      context "with firewall spec" do
        let(:extra_options) do
          {
            firewall_spec: {
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
            }
          }
        end

        it "generates firewall spec config" do
          expect(generated).to include(
            <<~EXPECTED.indent(2)
              firewall_spec = {
                internal: {
                  inbound_allow_type: "same-gvc"
                }
                external: {
                  inbound_allow_cidr: [
                    "0.0.0.0/0"
                  ],
                  outbound_allow_port: [
                    {
                      protocol: "tcp",
                      number: 80
                    }
                  ]
                }
              }
            EXPECTED
          )
        end
      end

      context "with load balancer" do
        let(:extra_options) do
          {
            load_balancer: {
              direct: {
                enabled: true,
                port: [
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
            }
          }
        end

        it "generates load balancer config" do
          expect(generated).to include(
            <<~EXPECTED.indent(2)
              load_balancer = {
                direct: {
                  enabled: true,
                  port: [
                    {
                      external_port: 8080,
                      protocol: "tcp",
                      scheme: "https",
                      container_port: 443
                    },
                    {
                      external_port: 443,
                      protocol: "udp",
                      scheme: "http"
                    }
                  ]
                }
                geo_location: {
                  enabled: true,
                  headers: {
                    asn: "asn",
                    city: "city",
                    country: "country",
                    region: "region"
                  }
                }
              }
            EXPECTED
          )
        end
      end
    end

    context "when workload's type is cron" do
      let(:type) { "cron" }

      let(:containers) do
        [
          {
            name: "daily-task",
            args: %w[bundle exec rake daily],
            image: "org/org-name/image/test:1",
            cpu: "50m",
            memory: "256Mi",
            inherit_env: true
          }
        ]
      end

      let(:extra_options) do
        {
          job: {
            active_deadline_seconds: 3600,
            concurrency_policy: "Forbid",
            history_limit: 5,
            restart_policy: "Never",
            schedule: "0 0 * * *"
          }
        }
      end

      it "generates correct config" do
        expect(generated).to include(
          <<~EXPECTED.indent(2)
            containers = {
              daily-task: {
                args: [
                  "bundle",
                  "exec",
                  "rake",
                  "daily"
                ],
                image: "org/org-name/image/test:1",
                cpu: "50m",
                memory: "256Mi",
                inherit_env: true
              }
            }
            job = {
              schedule: "0 0 * * *"
              concurrency_policy: "Forbid"
              history_limit: 5
              restart_policy: "Never"
              active_deadline_seconds: 3600
            }
          EXPECTED
        )
      end
    end
  end

  describe "#locals" do
    subject(:locals) { config.locals }

    let(:containers) { [rails_container, redis_container, postgres_container] }

    it "generates correct local variables", :aggregate_failures do
      expect(locals.keys).to contain_exactly("rails_envs.tf", "postgres_envs.tf")

      rails_envs = locals["rails_envs.tf"]
      expect(rails_envs).to be_an_instance_of(TerraformConfig::LocalVariable)
      expect(rails_envs.to_tf).to eq(
        <<~EXPECTED
          locals {
            rails_envs = {
              RACK_ENV = "production"
              RAILS_ENV = "production"
              SECRET_KEY_BASE = "TEST_SECRET_KEY_BASE"
            }
          }
        EXPECTED
      )

      postgres_envs = locals["postgres_envs.tf"]
      expect(postgres_envs).to be_an_instance_of(TerraformConfig::LocalVariable)
      expect(postgres_envs.to_tf).to eq(
        <<~EXPECTED
          locals {
            postgres_envs = {
              POSTGRES_PASSWORD = "TEST_DB_PASSWORD"
              TZ = "UTC"
            }
          }
        EXPECTED
      )
    end
  end

  def postgres_container # rubocop:disable Metrics/MethodLength
    {
      name: "postgres",
      args: [
        "-c",
        "cat /usr/local/bin/cpln-entrypoint.sh >> ./cpln-entrypoint.sh && " \
        "chmod u+x ./cpln-entrypoint.sh && " \
        "./cpln-entrypoint.sh postgres"
      ],
      command: "/bin/bash",
      cpu: "500m",
      env: [
        { name: "POSTGRES_PASSWORD", value: "TEST_DB_PASSWORD" },
        { name: "TZ", value: "UTC" }
      ],
      image: "ubuntu/postgres:14-22.04_beta",
      liveness_probe: {
        failure_threshold: 1,
        initial_delay_seconds: 10,
        period_seconds: 10,
        success_threshold: 1,
        tcp_socket: { port: 5432 },
        timeout_seconds: 1
      },
      readiness_probe: {
        failure_threshold: 1,
        initial_delay_seconds: 10,
        period_seconds: 10,
        success_threshold: 1,
        tcp_socket: { port: 5432 },
        timeout_seconds: 1
      },
      volumes: [
        {
          path: "/var/lib/postgresql/data",
          recovery_policy: "retain",
          uri: "cpln://volumeset/postgres-poc-vs"
        },
        {
          path: "/usr/local/bin/cpln-entrypoint.sh",
          recovery_policy: "retain",
          uri: "cpln://secret/postgres-poc-entrypoint-script"
        }
      ],
      inherit_env: false,
      memory: "512Mi"
    }
  end

  def redis_container
    {
      name: "redis",
      cpu: "500m",
      image: "redis",
      inherit_env: true,
      memory: "512Mi"
    }
  end

  def rails_container # rubocop:disable Metrics/MethodLength
    {
      name: "rails",
      cpu: "500m",
      env: [
        { name: "RACK_ENV", value: "production" },
        { name: "RAILS_ENV", value: "production" },
        { name: "SECRET_KEY_BASE", value: "TEST_SECRET_KEY_BASE" }
      ],
      image: "/org/org-name/image/rails:7",
      inherit_env: false,
      memory: "512Mi",
      ports: [{ number: 3000, protocol: "http" }]
    }
  end
end
