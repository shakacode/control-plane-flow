# frozen_string_literal: true

require "spec_helper"
require "pathname"

GEM_ROOT_PATH = Pathname.new(Dir.pwd)
GEM_TEMP_PATH = GEM_ROOT_PATH.join("tmp")
GENERATOR_PLAYGROUND_PATH = GEM_TEMP_PATH.join("sample-project")
TERRAFORM_CONFIG_DIR_PATH = GENERATOR_PLAYGROUND_PATH.join("terraform")

describe Command::Terraform::Generate do
  subject(:result) { run_cpflow_command(described_class::SUBCOMMAND_NAME, described_class::NAME, "-a", app) }

  let!(:app) { dummy_test_app }

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
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(TemplateParser).to receive(:template_dir).and_return(template_dir)
      # rubocop:enable RSpec/AnyInstance
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
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(TemplateParser).to receive(:parse).and_raise("error")
      # rubocop:enable RSpec/AnyInstance
    end

    it "generates only common config files" do
      config_file_paths.each { |config_file_path| expect(config_file_path).not_to exist }

      expect(result[:stderr]).to include("Error parsing templates: error")

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
    %w[gvc.tf identities.tf].map do |config_file_path|
      TERRAFORM_CONFIG_DIR_PATH.join(app, config_file_path)
    end
  end
end
