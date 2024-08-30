# frozen_string_literal: true

require "spec_helper"
require "pathname"

GEM_ROOT_PATH = Pathname.new(Dir.pwd)
GEM_TEMP_PATH = GEM_ROOT_PATH.join("tmp")
GENERATOR_PLAYGROUND_PATH = GEM_TEMP_PATH.join("sample-project")
TERRAFORM_CONFIG_DIR_PATH = GENERATOR_PLAYGROUND_PATH.join("terraform")

describe Command::Terraform::Generate do
  let!(:app) { dummy_test_app }

  before do
    FileUtils.rm_r(GENERATOR_PLAYGROUND_PATH) if Dir.exist?(GENERATOR_PLAYGROUND_PATH)
    FileUtils.mkdir_p GENERATOR_PLAYGROUND_PATH

    allow(Cpflow).to receive(:root_path).and_return(GENERATOR_PLAYGROUND_PATH)
  end

  after do
    FileUtils.rm_r GENERATOR_PLAYGROUND_PATH
  end

  it "generates terraform config files", :aggregate_failures do
    config_file_paths = %w[providers.tf gvc.tf identities.tf].map do |config_file_path|
      TERRAFORM_CONFIG_DIR_PATH.join(config_file_path)
    end

    config_file_paths.each { |config_file_path| expect(config_file_path).not_to exist }
    run_cpflow_command(described_class::SUBCOMMAND_NAME, described_class::NAME, "-a", app)
    expect(config_file_paths).to all(exist)
  end
end
