# frozen_string_literal: true

require "spec_helper"
require "pathname"

GEM_ROOT_PATH = Pathname.new(Dir.pwd)
GEM_TEMP_PATH = GEM_ROOT_PATH.join("tmp")
GENERATOR_PLAYGROUND_PATH = GEM_TEMP_PATH.join("sample-project")
TERRAFORM_CONFIG_DIR_PATH = GENERATOR_PLAYGROUND_PATH.join("terraform")

TEMPLATE_CONFIG_PATHS = %w[
  gvc
  identities
  secrets
  policies
  volumesets
  rails
  rails_envs
  rails-with-non-app-image
  rails-runner
  postgres
  postgres_envs
  maintenance
  maintenance_envs
  maintenance-with-external-image
  audit_contexts
].freeze

describe Command::Terraform::Generate do
  subject(:result) { run_cpflow_command(described_class::SUBCOMMAND_NAME, described_class::NAME, *options) }

  let!(:app) { dummy_test_app }
  let(:options) { ["-a", app] }

  before do
    FileUtils.rm_rf(GENERATOR_PLAYGROUND_PATH)
    FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH)

    FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("lib/core/terraform_config/workload"))
    FileUtils.copy_entry(
      Cpflow.root_path.join("lib/core/terraform_config/workload"),
      GENERATOR_PLAYGROUND_PATH.join("lib/core/terraform_config/workload/")
    )

    allow(Cpflow).to receive(:root_path).and_return(GENERATOR_PLAYGROUND_PATH)
  end

  after do
    FileUtils.rm_rf GENERATOR_PLAYGROUND_PATH
  end

  shared_examples "generates terraform config files" do |status = ExitCode::SUCCESS|
    specify do
      all_config_paths.each { |path| expect(path).not_to exist }

      expect(result[:status]).to eq(status)
      expect(result[:stderr]).to err_msg ? include(err_msg) : be_empty

      expect(expected_config_paths).to all(exist)
      (all_config_paths - expected_config_paths).each { |path| expect(path).not_to exist }
    end
  end

  shared_examples "does not generate any terraform config files" do |err_msg|
    it "fails with an error" do
      all_config_paths.each { |path| expect(path).not_to exist }

      expect(result[:status]).to eq(ExitCode::ERROR_DEFAULT)
      expect(result[:stderr]).to include(err_msg)

      all_config_paths.each { |path| expect(path).not_to exist }
    end
  end

  it_behaves_like "generates terraform config files" do
    let(:expected_config_paths) { all_config_paths }
    let(:err_msg) { nil }
  end

  context "when templates folder is empty" do
    let(:template_dir) { "non-existing-folder" }

    before do
      allow_any_instance_of(TemplateParser).to receive(:template_dir).and_return(template_dir) # rubocop:disable RSpec/AnyInstance
    end

    it_behaves_like "generates terraform config files" do
      let(:expected_config_paths) { provider_config_paths + workload_module_config_paths }
      let(:err_msg) { "No templates found in #{template_dir}" }
    end
  end

  context "when template parsing fails" do
    before do
      allow_any_instance_of(TemplateParser).to receive(:parse).and_raise("error") # rubocop:disable RSpec/AnyInstance
    end

    it_behaves_like "generates terraform config files" do
      let(:expected_config_paths) { provider_config_paths + workload_module_config_paths }
      let(:err_msg) { "Error parsing templates: error" }
    end
  end

  context "when --dir option is outside of project dir" do
    let(:options) { ["-a", app, "--dir", dir.to_s] }
    let(:dir) { GEM_TEMP_PATH.join("path-outside-of-project") }

    after do
      FileUtils.rm_rf(dir)
    end

    it_behaves_like "does not generate any terraform config files",
                    "Directory to save terraform configuration files cannot be outside of current directory"
  end

  context "when terraform config directory creation fails" do
    before do
      allow(FileUtils).to receive(:mkdir_p).and_raise("error")
    end

    it_behaves_like "does not generate any terraform config files", "Invalid directory: error"
  end

  context "when required provider config generation fails" do
    let(:required_provider_config_stub) { instance_double(TerraformConfig::RequiredProvider) }

    before do
      allow(TerraformConfig::RequiredProvider).to receive(:new).and_return(required_provider_config_stub)
      allow(required_provider_config_stub).to receive(:to_tf).and_raise("error")
    end

    it_behaves_like "generates terraform config files", ExitCode::ERROR_DEFAULT do
      let(:expected_config_paths) { workload_module_config_paths }
      let(:err_msg) { "Failed to generate provider config files: error" }
    end
  end

  context "when InvalidTemplateError is raised" do
    before do
      allow_any_instance_of(TerraformConfig::Generator).to receive(:tf_configs).and_raise( # rubocop:disable RSpec/AnyInstance
        TerraformConfig::Generator::InvalidTemplateError, "Invalid template: error message"
      )
    end

    it_behaves_like "generates terraform config files" do
      let(:expected_config_paths) { provider_config_paths + workload_module_config_paths }
      let(:err_msg) { "Invalid template: error message" }
    end
  end

  def all_config_paths
    workload_module_config_paths + provider_config_paths + template_config_paths
  end

  def workload_module_config_paths
    %w[required_providers main variables].map { |name| TERRAFORM_CONFIG_DIR_PATH.join("workload", "#{name}.tf") }
  end

  def provider_config_paths
    %w[required_providers providers].map { |name| config_path("#{name}.tf") }
  end

  def template_config_paths
    TEMPLATE_CONFIG_PATHS.map { |name| config_path("#{name}.tf") }
  end

  def config_path(name)
    TERRAFORM_CONFIG_DIR_PATH.join(app, name)
  end
end
