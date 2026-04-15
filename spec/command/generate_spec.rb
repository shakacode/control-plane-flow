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
  let(:entrypoint_path) { CONTROLPLANE_CONFIG_DIR_PATH.join("entrypoint.sh") }
  let(:dockerfile_path) { CONTROLPLANE_CONFIG_DIR_PATH.join("Dockerfile") }

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
        expect(dockerfile_path).to exist
        expect(entrypoint_path).to exist
        expect(entrypoint_path).to be_executable

        dockerfile_content = dockerfile_path.read
        expect(dockerfile_content).to include("FROM docker.io/library/node:22-bullseye-slim AS node")
        expect(dockerfile_content).to include("COPY --from=node /usr/local/ /usr/local/")
        expect(dockerfile_content).to include("exec corepack yarn \"$@\"")
        expect(dockerfile_content).to include("exec corepack pnpm \"$@\"")
        expect(dockerfile_content).to include(
          "package_manager=\"$(node -p \"require('./package.json').packageManager || ''\")\""
        )
        expect(dockerfile_content).to include("corepack prepare \"$package_manager\" --activate &&")
        expect(dockerfile_content).to include("npm install -g yarn &&")
        expect(dockerfile_content).to include("corepack yarn install --immutable")
        expect(dockerfile_content).to include("yarn install --immutable || yarn install --frozen-lockfile")
        expect(dockerfile_content).to include("corepack pnpm install --frozen-lockfile")
        expect(dockerfile_content).to include("npm ci")
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
