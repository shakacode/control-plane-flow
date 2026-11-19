# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "tmpdir"
require "yaml"

RSpec.describe "Production promotion environment parity", :aggregate_failures do # rubocop:disable RSpec/DescribeClass
  def run_parity_step(mode, production_names: %w[COMMON PROD_ONLY])
    Dir.mktmpdir do |dir|
      write_cpln_stub(File.join(dir, "cpln"))
      Open3.capture3(parity_env(dir, mode, production_names), "bash", stdin_data: parity_script)
    end
  end

  def write_cpln_stub(path)
    File.write(path, <<~'BASH')
      #!/bin/bash
      echo "cpln $1" >&2
      case "$*" in
        *'--org stage '*) printf '%s\n' "$TEST_STAGING_RESPONSE" ;;
        *'--org prod '*) printf '%s\n' "$TEST_PRODUCTION_RESPONSE" ;;
        *) exit 2 ;;
      esac
    BASH
    File.chmod(0o755, path)
  end

  def parity_env(dir, mode, production_names)
    { "PATH" => "#{dir}:#{ENV.fetch('PATH')}", "BASH_ENV" => "/dev/null", "ENV_PARITY_CHECK" => mode,
      "CPLN_ORG_STAGING" => "stage", "CPLN_ORG_PRODUCTION" => "prod", "STAGING_APP_NAME" => "app-stage",
      "PRODUCTION_APP_NAME" => "app-prod", "CPLN_TOKEN_STAGING" => "test-staging-token",
      "CPLN_TOKEN_PRODUCTION" => "test-production-token", "WORKLOAD_NAMES" => "rails",
      "TEST_STAGING_RESPONSE" => cpln_response(%w[COMMON STAGE_ONLY]),
      "TEST_PRODUCTION_RESPONSE" => cpln_response(production_names) }
  end

  def cpln_response(names)
    env = names.map { |name| { name: name } }
    JSON.generate(spec: { env: env, containers: [{ env: env }] })
  end

  %w[. lib/github_flow_templates].each do |root|
    context "with the workflow under #{root}" do
      let(:parity_script) do
        workflow = YAML.safe_load_file("#{root}/.github/workflows/cpflow-promote-staging-to-production.yml")
        steps = workflow.fetch("jobs").fetch("promote-to-production").fetch("steps")
        steps.find { |step| step["name"] == "Verify production environment variables" }.fetch("run")
      end

      [nil, "false"].each do |mode|
        it "skips Control Plane lookups and emits a notice with ENV_PARITY_CHECK=#{mode.inspect}" do
          stdout, stderr, status = run_parity_step(mode)

          expect(status).to be_success
          expect(stdout).to include("::notice::", "Set ENV_PARITY_CHECK=true to enable it")
          expect(stderr).to be_empty
        end
      end

      it "fails for staging-only names and warns about production-only names when enabled" do
        stdout, _, status = run_parity_step("true")

        expect(status).not_to be_success
        expect(stdout).to include("::error::Production GVC", "::error::Production workload", "STAGE_ONLY")
        expect(stdout).to include("::warning::Production GVC", "::warning::Production workload", "PROD_ONLY")
      end

      it "allows production-only names when enabled" do
        stdout, _, status = run_parity_step("true", production_names: %w[COMMON STAGE_ONLY PROD_ONLY])

        expect(status).to be_success
        expect(stdout).to include("::warning::", "PROD_ONLY")
      end

      it "rejects a mistyped value before calling Control Plane" do
        stdout, stderr, status = run_parity_step("True")

        expect(status).not_to be_success
        expect(stdout).to include("::error::ENV_PARITY_CHECK must be true or false")
        expect(stderr).to be_empty
      end
    end
  end
end
