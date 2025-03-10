# frozen_string_literal: true

require "spec_helper"
require "pathname"

GEM_ROOT_PATH = Pathname.new(Dir.pwd)
GEM_TEMP_PATH = GEM_ROOT_PATH.join("tmp")
GENERATOR_PLAYGROUND_PATH = GEM_TEMP_PATH.join("sample-project")
CONTROLPLANE_CONFIG_DIR_PATH = GENERATOR_PLAYGROUND_PATH.join(".controlplane")

def inside_dir(path)
  original_working_dir = Dir.pwd
  Dir.chdir path
  yield if block_given?
ensure
  Dir.chdir original_working_dir
end

describe Command::Generate, :enable_validations, :without_config_file do
  let(:controlplane_config_file_path) { CONTROLPLANE_CONFIG_DIR_PATH.join("controlplane.yml") }

  before do
    FileUtils.rm_r(GENERATOR_PLAYGROUND_PATH) if Dir.exist?(GENERATOR_PLAYGROUND_PATH)
    FileUtils.mkdir_p GENERATOR_PLAYGROUND_PATH
  end

  after do
    FileUtils.rm_r GENERATOR_PLAYGROUND_PATH
  end

  context "when no configuration exist in the project" do
    it "generates base config files" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        expect(controlplane_config_file_path).not_to exist

        Cpflow::Cli.start([described_class::NAME])

        expect(controlplane_config_file_path).to exist
      end
    end
  end

  context "when .controlplane directory already exist" do
    let(:controlplane_config_dir) { controlplane_config_file_path.parent }

    before do
      Dir.mkdir(controlplane_config_dir)
    end

    it "doesn't generates base config files" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        expect(controlplane_config_dir).to exist

        expect do
          Cpflow::Cli.start([described_class::NAME])
        end.to output(/already exist/).to_stderr

        expect(controlplane_config_file_path).not_to exist
      end
    end
  end
end
