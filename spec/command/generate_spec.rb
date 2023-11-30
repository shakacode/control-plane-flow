# frozen_string_literal: true

require "spec_helper"
require "pathname"

GEM_ROOT_PATH = Pathname.new(Dir.pwd)
GEM_TEMP_PATH = GEM_ROOT_PATH.join("tmp")
GENERATOR_PLAYGROUND_PATH = GEM_TEMP_PATH.join("sample-project")
CONTROLPLANE_CONFIG_DIR_PATH = GENERATOR_PLAYGROUND_PATH.join(".controlplane")
CPL_EXECUTABLE_PATH = GEM_ROOT_PATH.join("bin", "cpl")

def inside_dir(path)
  original_working_dir = Dir.pwd
  Dir.chdir path
  yield if block_given?
ensure
  Dir.chdir original_working_dir
end

describe Command::Generate do
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
        Cpl::Cli.start([described_class::NAME])
        controlplane_config_file_path = CONTROLPLANE_CONFIG_DIR_PATH.join("controlplane.yml")
        expect(controlplane_config_file_path).to exist
      end
    end
  end
end
