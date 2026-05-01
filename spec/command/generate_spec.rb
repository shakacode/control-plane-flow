# frozen_string_literal: true

require "spec_helper"
require "pathname"

GEM_ROOT_PATH = Pathname.new(Dir.pwd)
GEM_TEMP_PATH = GEM_ROOT_PATH.join("tmp")
GENERATOR_PLAYGROUND_PATH = GEM_TEMP_PATH.join("sample-project")
CONTROLPLANE_CONFIG_DIR_PATH = GENERATOR_PLAYGROUND_PATH.join(".controlplane")

def controlplane_config_file_path
  CONTROLPLANE_CONFIG_DIR_PATH.join("controlplane.yml")
end

def release_script_path
  CONTROLPLANE_CONFIG_DIR_PATH.join("release_script.sh")
end

def entrypoint_path
  CONTROLPLANE_CONFIG_DIR_PATH.join("entrypoint.sh")
end

def dockerfile_path
  CONTROLPLANE_CONFIG_DIR_PATH.join("Dockerfile")
end

def app_template_path
  CONTROLPLANE_CONFIG_DIR_PATH.join("templates/app.yml")
end

def rails_template_path
  CONTROLPLANE_CONFIG_DIR_PATH.join("templates/rails.yml")
end

def postgres_template_path
  CONTROLPLANE_CONFIG_DIR_PATH.join("templates/postgres.yml")
end

def db_template_path
  CONTROLPLANE_CONFIG_DIR_PATH.join("templates/db.yml")
end

def storage_template_path
  CONTROLPLANE_CONFIG_DIR_PATH.join("templates/storage.yml")
end

def generated_ruby_arg
  dockerfile_path.read.lines.find { |line| line.start_with?("ARG RUBY_VERSION=") }
end

describe Command::Generate, :enable_validations, :without_config_file do
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
        expect(release_script_path).to exist
        expect(entrypoint_path).to be_executable
        expect(release_script_path).to be_executable

        controlplane_content = controlplane_config_file_path.read
        dockerfile_content = dockerfile_path.read
        app_template_content = app_template_path.read
        rails_template_content = rails_template_path.read

        expect(controlplane_content).to include("sample-project-staging")
        expect(controlplane_content).to include("sample-project-review")
        expect(controlplane_content).to include("sample-project-production")
        expect(controlplane_content).to include("setup_app_templates:")
        expect(controlplane_content).to include("- postgres")
        expect(controlplane_content).to include("release_script: release_script.sh")
        expect(controlplane_content).to include("#   post_creation: bundle exec rails db:prepare")
        expect(controlplane_content).to include("#   pre_deletion: bundle exec rails db:drop")
        expect(generated_ruby_arg).to eq("ARG RUBY_VERSION=3.3\n")
        expect(dockerfile_content).to include("FROM docker.io/library/node:22-bookworm-slim AS node")
        expect(dockerfile_content).to include("COPY --from=node /usr/local/bin/node /usr/local/bin/node")
        expect(dockerfile_content).not_to include("RUN apt-get update")
        expect(dockerfile_content).to include("bundle config set with 'production'")
        expect(dockerfile_content).not_to include("bundle config set with 'staging production'")
        expect(dockerfile_content).to include("exec corepack yarn \"$@\"")
        expect(dockerfile_content).to include("exec corepack pnpm \"$@\"")
        expect(dockerfile_content).to include(
          "package_manager=\"$(node -p \"require('./package.json').packageManager || ''\")\""
        )
        expect(dockerfile_content).to include("corepack prepare \"$package_manager\" --activate &&")
        expect(dockerfile_content).to include("ARG YARN_CLASSIC_VERSION=1.22.22")
        expect(dockerfile_content).to include("ARG PNPM_FALLBACK_VERSION=9.12.3")
        expect(dockerfile_content).to include('npm install -g "yarn@${YARN_CLASSIC_VERSION}"')
        expect(dockerfile_content).to include('corepack prepare "pnpm@${PNPM_FALLBACK_VERSION}" --activate')
        expect(dockerfile_content).to include("corepack yarn install --immutable")
        expect(dockerfile_content).to include("yarn install --immutable || yarn install --frozen-lockfile")
        expect(dockerfile_content).to include("corepack pnpm install --frozen-lockfile")
        expect(dockerfile_content).to include("npm ci")
        expect(dockerfile_content).not_to include("react_on_rails:generate_packs")
        expect(app_template_content).to include("RAILS_LOG_TO_STDOUT")
        expect(app_template_content).to include("SECRET_KEY_BASE")
        expect(rails_template_content).to include("minScale: 1")
        expect(rails_template_content).to include("timeoutSeconds: 60")
        expect(entrypoint_path.read).to include("executing '$*'")
        expect(postgres_template_path).to exist
        expect(release_script_path.read).to include("SECRET_KEY_BASE=\"${SECRET_KEY_BASE:-precompile_placeholder}\"")
      end
    end

    it "skips startup checks for the local-only generator command" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        Cpflow::Cli.start([described_class::NAME])

        expect(Cpflow::Cli).not_to have_received(:check_cpln_version)
        expect(Cpflow::Cli).not_to have_received(:check_cpflow_version)
      end
    end
  end

  context "when .ruby-version exists" do
    before do
      GENERATOR_PLAYGROUND_PATH.join(".ruby-version").write("ruby-3.3.6\n")
    end

    it "uses the .ruby-version value for the Docker base image" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        Cpflow::Cli.start([described_class::NAME])

        expect(generated_ruby_arg).to eq("ARG RUBY_VERSION=3.3.6\n")
      end
    end
  end

  context "when .tool-versions exists" do
    before do
      GENERATOR_PLAYGROUND_PATH.join(".tool-versions").write("nodejs 22.15.0\nruby 3.2.9\n")
    end

    it "uses the ruby version from .tool-versions" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        Cpflow::Cli.start([described_class::NAME])

        expect(generated_ruby_arg).to eq("ARG RUBY_VERSION=3.2.9\n")
      end
    end
  end

  context "when only a Gemfile ruby directive exists" do
    before do
      GENERATOR_PLAYGROUND_PATH.join("Gemfile").write(<<~GEMFILE)
        source "https://rubygems.org"

        ruby ">= 3.3"
      GEMFILE
    end

    it "uses the Gemfile ruby requirement as the Docker base image hint" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        Cpflow::Cli.start([described_class::NAME])

        expect(generated_ruby_arg).to eq("ARG RUBY_VERSION=3.3\n")
      end
    end
  end

  context "when a Gemfile contains a non-literal ruby helper before a ruby directive" do
    before do
      GENERATOR_PLAYGROUND_PATH.join("Gemfile").write(<<~GEMFILE)
        source "https://rubygems.org"

        ruby RUBY_VERSION
        ruby "3.2.9"
      GEMFILE
    end

    it "uses the literal ruby directive" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        Cpflow::Cli.start([described_class::NAME])

        expect(generated_ruby_arg).to eq("ARG RUBY_VERSION=3.2.9\n")
      end
    end
  end

  context "when production uses sqlite3" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/database.yml").write(<<~YAML)
        default: &default
          adapter: sqlite3
          pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
          timeout: 5000

        production:
          <<: *default
          database: db/production.sqlite3
      YAML
    end

    it "generates sqlite-backed persistent volume templates instead of postgres" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        Cpflow::Cli.start([described_class::NAME])

        controlplane_content = controlplane_config_file_path.read

        expect(controlplane_content).to include("- db")
        expect(controlplane_content).to include("- storage")
        expect(controlplane_content).not_to include("- postgres")
        expect(postgres_template_path).not_to exist
        expect(db_template_path).to exist
        expect(storage_template_path).to exist
        expect(app_template_path.read).not_to include("DATABASE_URL")
        expect(rails_template_path.read).to include("uri: cpln://volumeset/app-db")
        expect(rails_template_path.read).to include("uri: cpln://volumeset/app-storage")
        expect(release_script_path.read).to include("mkdir -p db storage")
      end
    end
  end

  context "when only non-production environments use sqlite3" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/database.yml").write(<<~YAML)
        default: &default
          adapter: sqlite3
          pool: 5
          timeout: 5000

        production:
          <<: *default
          adapter: postgresql
          database: sample_project_production
      YAML
    end

    it "keeps the postgres-backed templates" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        Cpflow::Cli.start([described_class::NAME])

        controlplane_content = controlplane_config_file_path.read

        expect(controlplane_content).to include("- postgres")
        expect(controlplane_content).not_to include("- db")
        expect(controlplane_content).not_to include("- storage")
        expect(postgres_template_path).to exist
        expect(db_template_path).not_to exist
        expect(storage_template_path).not_to exist
        expect(app_template_path.read).to include("DATABASE_URL")
        expect(release_script_path.read).not_to include("mkdir -p db storage")
      end
    end
  end

  context "when shakapacker config defines a precompile hook" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/shakapacker.yml").write(<<~YAML)
        default: &default
          precompile_hook: "rake react_on_rails:generate_packs"
      YAML
    end

    it "runs the hook before assets precompile in the generated Dockerfile" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        Cpflow::Cli.start([described_class::NAME])

        dockerfile_content = dockerfile_path.read

        expect(dockerfile_content).to include("RUN bundle exec rake react_on_rails:generate_packs")
        expect(
          dockerfile_content.index("RUN bundle exec rake react_on_rails:generate_packs")
        ).to be < dockerfile_content.index("RUN rails assets:precompile")
      end
    end
  end

  context "when shakapacker config defines a multiline precompile hook" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/shakapacker.yml").write(<<~YAML)
        default: &default
          precompile_hook: |
            rake react_on_rails:generate_packs
            USER root
      YAML
    end

    it "skips the hook instead of injecting additional Dockerfile instructions" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        expect do
          Cpflow::Cli.start([described_class::NAME])
        end.to output(/Skipping asset precompile hook/).to_stderr

        dockerfile_content = dockerfile_path.read

        expect(dockerfile_content).not_to include("RUN rake react_on_rails:generate_packs")
        expect(dockerfile_content).not_to include("USER root")
      end
    end
  end

  context "when React on Rails auto bundle generation is enabled" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config/initializers"))
      GENERATOR_PLAYGROUND_PATH.join("config/initializers/react_on_rails.rb").write(<<~RUBY)
        ReactOnRails.configure do |config|
          config.auto_load_bundle = true
        end
      RUBY
    end

    it "adds the React on Rails pack generation step before assets precompile" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        Cpflow::Cli.start([described_class::NAME])

        expect(dockerfile_path.read).to include("RUN bundle exec rake react_on_rails:generate_packs")
      end
    end
  end

  context "when .controlplane directory already exist" do
    it "doesn't generates base config files" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        controlplane_config_dir = controlplane_config_file_path.parent
        Dir.mkdir(controlplane_config_dir)

        expect(controlplane_config_dir).to exist

        expect do
          Cpflow::Cli.start([described_class::NAME])
        end.to output(/already exist/).to_stderr

        expect(controlplane_config_file_path).not_to exist
      end
    end
  end
end
