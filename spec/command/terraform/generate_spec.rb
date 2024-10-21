# frozen_string_literal: true

require "spec_helper"
require "pathname"

GEM_ROOT_PATH = Pathname.new(Dir.pwd)
GEM_TEMP_PATH = GEM_ROOT_PATH.join("tmp")
GENERATOR_PLAYGROUND_PATH = GEM_TEMP_PATH.join("sample-project")
TERRAFORM_CONFIG_DIR_PATH = GENERATOR_PLAYGROUND_PATH.join("terraform")

describe Command::Terraform::Generate do
  subject(:result) { run_cpflow_command(described_class::SUBCOMMAND_NAME, described_class::NAME, *options) }

  let!(:app) { dummy_test_app }
  let(:options) { ["-a", app] }

  before do
    FileUtils.rm_rf(GENERATOR_PLAYGROUND_PATH)
    FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH)
    allow(Cpflow).to receive(:root_path).and_return(GENERATOR_PLAYGROUND_PATH)
  end

  after do
    FileUtils.rm_rf GENERATOR_PLAYGROUND_PATH
  end

  it "generates terraform config files", :aggregate_failures do
    config_file_paths.each { |config_file_path| expect(config_file_path).not_to exist }

    expect(result[:status]).to eq(0)

    expect(config_file_paths).to all(exist)
  end

  context "when templates folder is empty" do
    let(:template_dir) { "non-existing-folder" }

    before do
      allow_any_instance_of(TemplateParser).to receive(:template_dir).and_return(template_dir) # rubocop:disable RSpec/AnyInstance
    end

    it "generates only common config files" do
      config_file_paths.each { |config_file_path| expect(config_file_path).not_to exist }

      expect(result[:stderr]).to include("No templates found in #{template_dir}")

      expect(common_config_files).to all(exist)
      app_config_files.each { |config_file_path| expect(config_file_path).not_to exist }
    end
  end

  context "when template parsing fails" do
    before do
      allow_any_instance_of(TemplateParser).to receive(:parse).and_raise("error") # rubocop:disable RSpec/AnyInstance
    end

    it "generates only common config files" do
      config_file_paths.each { |config_file_path| expect(config_file_path).not_to exist }

      expect(result[:stderr]).to include("Error parsing templates: error")

      expect(common_config_files).to all(exist)
      app_config_files.each { |config_file_path| expect(config_file_path).not_to exist }
    end
  end

  context "when --dir option is outside of project dir" do
    let(:options) { ["-a", app, "--dir", GEM_TEMP_PATH.join("path-outside-of-project").to_s] }

    it "aborts command execution" do
      expect(result[:status]).to eq(ExitCode::ERROR_DEFAULT)
      expect(result[:stderr]).to include(
        "Directory to save terraform configuration files cannot be outside of current directory"
      )
    end
  end

  context "when terraform config directory creation fails" do
    before do
      allow(FileUtils).to receive(:mkdir_p).and_raise("error")
    end

    it "aborts command execution" do
      expect(result[:status]).to eq(ExitCode::ERROR_DEFAULT)
      expect(result[:stderr]).to include("error")
    end
  end

  context "when InvalidTemplateError is raised" do
    before do
      allow_any_instance_of(TerraformConfig::Generator).to receive(:tf_config).and_raise( # rubocop:disable RSpec/AnyInstance
        TerraformConfig::Generator::InvalidTemplateError, "Invalid template: error message"
      )
    end

    it "generates common config files and warns about invalid template" do
      config_file_paths.each { |config_file_path| expect(config_file_path).not_to exist }

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Invalid template: error message")

      expect(common_config_files).to all(exist)
      app_config_files.each { |config_file_path| expect(config_file_path).not_to exist }
    end
  end

  def config_file_paths
    common_config_files + app_config_files
  end

  def common_config_files
    [TERRAFORM_CONFIG_DIR_PATH.join("providers.tf")]
  end

  def app_config_files
    %w[gvc.tf identities.tf secrets.tf policies.tf volumesets.tf].map do |config_file_path|
      TERRAFORM_CONFIG_DIR_PATH.join(app, config_file_path)
    end
  end
end
