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

def dockerignore_path
  GENERATOR_PLAYGROUND_PATH.join(".dockerignore")
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
        expect(dockerignore_path).to exist
        expect(dockerignore_path.read).to include("config/master.key")
        expect(dockerignore_path.read).to include("config/credentials/*.key")
        expect(entrypoint_path).to exist
        expect(release_script_path).to exist
        expect(entrypoint_path).to be_executable
        expect(release_script_path).to be_executable

        controlplane_content = controlplane_config_file_path.read
        dockerfile_content = dockerfile_path.read
        app_template_content = app_template_path.read
        rails_template_content = rails_template_path.read
        postgres_template_content = postgres_template_path.read

        expect(controlplane_content).to include("sample-project-staging")
        expect(controlplane_content).to include("sample-project-review")
        expect(controlplane_content).to include("sample-project-production")
        expect(controlplane_content).to include("setup_app_templates:")
        expect(controlplane_content).to include("- postgres")
        expect(controlplane_content).to include("release_script: release_script.sh")
        expect(controlplane_content).to include("#   post_creation: bundle exec rails db:prepare")
        expect(controlplane_content).to include("# Uncomment to automatically initialize review-app databases:")
        expect(controlplane_content).not_to include("tear down")
        expect(controlplane_content).not_to match(/pre_deletion:.*db:drop/)
        expect(generated_ruby_arg).to eq("ARG RUBY_VERSION=3.3\n")
        expect(dockerfile_content).to include("FROM docker.io/library/node:22-bookworm-slim AS node")
        expect(dockerfile_content).to include("COPY --from=node /usr/local/bin/node /usr/local/bin/node")
        expect(dockerfile_content).not_to include("COPY --from=node /usr/local/bin/npm")
        expect(dockerfile_content).not_to include("COPY --from=node /usr/local/bin/npx")
        expect(dockerfile_content).not_to include("COPY --from=node /usr/local/bin/corepack")
        expect(dockerfile_content).to include(
          "ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm"
        )
        expect(dockerfile_content).to include(
          "ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx"
        )
        expect(dockerfile_content).to include(
          "ln -sf ../lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack"
        )
        expect(dockerfile_content).to match(
          %r{chmod[ ]\+x[ ]/usr/local/lib/node_modules/npm/bin/npm-cli\.js[ ]\\\n\s+
             /usr/local/lib/node_modules/npm/bin/npx-cli\.js[ ]\\\n\s+
             /usr/local/lib/node_modules/corepack/dist/corepack\.js[ ]&&[ ]\\\n\s+
             node[ ]--version[ ]&&[ ]npm[ ]--version[ ]&&[ ]corepack[ ]--version}x
        )
        expect(dockerfile_content).to include("apt-get install --no-install-recommends -y build-essential")
        expect(dockerfile_content).to include("apt-get purge -y --auto-remove build-essential")
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
        expect(dockerfile_content).not_to include("ENV SECRET_KEY_BASE=NOT_USED_NON_BLANK")
        expect(dockerfile_content).to include("RUN SECRET_KEY_BASE=NOT_USED_NON_BLANK rails assets:precompile")
        expect(dockerignore_path.read).to include("config/master.key")
        expect(dockerignore_path.read).to include(".git")
        expect(dockerfile_content).not_to include("react_on_rails:generate_packs")
        expect(app_template_content).to include('name: "{{APP_NAME}}"')
        expect(app_template_content).to include('"{{APP_LOCATION_LINK}}"')
        expect(app_template_content).to include("RAILS_LOG_TO_STDOUT")
        expect(app_template_content).to include("SECRET_KEY_BASE")
        expect(rails_template_content).to include('image: "{{APP_IMAGE_LINK}}"')
        expect(rails_template_content).to include('identityLink: "{{APP_IDENTITY_LINK}}"')
        expect(rails_template_content).to include("minScale: 1")
        expect(rails_template_content).to include("timeoutSeconds: 60")
        expect(postgres_template_content).to include('name: "{{APP_NAME}}-pg"')
        expect(postgres_template_content).to include('name: "{{APP_NAME}}-pg-vs"')
        expect(postgres_template_content).to include('name: "{{APP_NAME}}-pg-identity"')
        expect(postgres_template_content).to include('"cpln://volumeset/{{APP_NAME}}-pg-vs"')
        expect(postgres_template_content).to include('"cpln://secret/{{APP_NAME}}-pg.password"')
        expect(postgres_template_content).to include('"//identity/{{APP_NAME}}-pg-identity"')
        expect(postgres_template_content).to include('- "{{APP_IDENTITY_LINK}}"')
        entrypoint_content = entrypoint_path.read
        expect(entrypoint_content).to include("set -e")
        expect(dockerfile_content).to include("RUN chmod +x /app/entrypoint.sh")
        expect(entrypoint_content).to match(%r{^\s*\./bin/rails db:prepare$})
        expect(entrypoint_content).to include("is_rails_server_command")
        expect(entrypoint_content).to include("env-prefixed, flag-free Thruster invocations")
        expect(entrypoint_content).to include("Thruster may be wrapped with its own `bundle exec`")
        expect(entrypoint_content).to include('[ "${1:-}" = "env" ]')
        expect(entrypoint_content).to include('"rails" ] || [')
        expect(entrypoint_content).to include('"bin/rails" ] || [')
        expect(entrypoint_content).to include('"server" ] || [')
        expect(entrypoint_content).to include('"s" ]')
        expect(entrypoint_content).to include('exec "$@"')
        expect(entrypoint_content).not_to include("$*")
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
        expect(app_template_path.read).to include('name: "{{APP_NAME}}"')
        expect(app_template_path.read).to include('"{{APP_LOCATION_LINK}}"')
        expect(app_template_path.read).to include('"cpln://secret/{{APP_SECRETS}}.SECRET_KEY_BASE"')
        expect(rails_template_path.read).to include('image: "{{APP_IMAGE_LINK}}"')
        expect(rails_template_path.read).to include('identityLink: "{{APP_IDENTITY_LINK}}"')
        expect(app_template_path.read).not_to include("DATABASE_URL")
        expect(entrypoint_path.read).to include(
          "prepare_sqlite_database /app/db/production.sqlite3 /app/data/db/production.sqlite3 " \
          "/app/data/production.sqlite3"
        )
        expect(rails_template_path.read).to include("path: /app/data")
        expect(rails_template_path.read).not_to include("path: /app/db")
        expect(rails_template_path.read).to include("uri: cpln://volumeset/app-db")
        expect(rails_template_path.read).to include("uri: cpln://volumeset/app-storage")
        expect(release_script_path.read).to include("mkdir -p data storage")
      end
    end

    it "uses a database at the legacy volume root with its sidecars intact" do
      Dir.mktmpdir("cpflow-sqlite-migration") do |root|
        source = Pathname.new(root).join("app/db/production.sqlite3")
        target = Pathname.new(root).join("app/data/db/production.sqlite3")
        legacy = Pathname.new(root).join("app/data/production.sqlite3")
        FileUtils.mkdir_p(source.dirname)
        FileUtils.mkdir_p(legacy.dirname)
        source.write("image seed")
        legacy.write("legacy database")
        legacy.sub_ext(".sqlite3-wal").write("wal")
        legacy.sub_ext(".sqlite3-shm").write("shm")
        legacy.sub_ext(".sqlite3-journal").write("journal")
        arguments = [source, target, legacy].map { |path| Shellwords.shellescape(path.to_s) }
        script = <<~SH
          #{Command::Generator::SQLITE_DATABASE_PREPARE_FUNCTION}
          prepare_sqlite_database #{arguments.join(' ')}
        SH

        _stdout, stderr, status = Open3.capture3("/bin/sh", stdin_data: script)

        expect(status).to be_success, stderr
        expect(target).not_to exist
        expect(source).to be_symlink
        expect(source.read).to eq("legacy database")
        expect(legacy.read).to eq("legacy database")
        expect(legacy.sub_ext(".sqlite3-wal").read).to eq("wal")
        expect(legacy.sub_ext(".sqlite3-shm").read).to eq("shm")
        expect(legacy.sub_ext(".sqlite3-journal").read).to eq("journal")
      end
    end

    it "does not overwrite a persistent database when seed setup runs concurrently" do
      Dir.mktmpdir("cpflow-sqlite-race") do |root|
        first_source = Pathname.new(root).join("first/production.sqlite3")
        second_source = Pathname.new(root).join("second/production.sqlite3")
        target = Pathname.new(root).join("data/production.sqlite3")
        FileUtils.mkdir_p(first_source.dirname)
        FileUtils.mkdir_p(second_source.dirname)
        first_source.write("first seed")
        second_source.write("second seed")
        first_arguments = [first_source, target].map { |path| Shellwords.shellescape(path.to_s) }
        second_arguments = [second_source, target].map { |path| Shellwords.shellescape(path.to_s) }
        script = <<~SH
          #{Command::Generator::SQLITE_DATABASE_PREPARE_FUNCTION}
          prepare_sqlite_database #{first_arguments.join(' ')} &
          prepare_sqlite_database #{second_arguments.join(' ')} &
          wait
        SH

        _stdout, stderr, status = Open3.capture3("/bin/sh", stdin_data: script)

        expect(status).to be_success, stderr
        expect(["first seed", "second seed"].include?(target.read)).to be(true)
        expect(first_source).to be_symlink
        expect(second_source).to be_symlink
      end
    end
  end

  context "when the production SQLite path is dynamic" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/database.yml").write(<<~YAML)
        production:
          adapter: sqlite3
          database: <%= ENV.fetch("SQLITE_PATH") %>
      YAML
    end

    it "fails before generating a scaffold that cannot persist the database" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        expect { Cpflow::Cli.start([described_class::NAME]) }
          .to raise_error(Cpflow::Error, /must be literal file paths/)
        expect(controlplane_config_file_path).not_to exist
      end
    end
  end

  context "when a dynamic URL is paired with a SQLite adapter" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/database.yml").write(<<~YAML)
        production:
          adapter: sqlite3
          url: <%= ENV.fetch("DATABASE_URL") %>
      YAML
    end

    it "fails instead of generating a Postgres scaffold" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        expect { Cpflow::Cli.start([described_class::NAME]) }
          .to raise_error(Cpflow::Error, /must be literal file paths/)
        expect(controlplane_config_file_path).not_to exist
      end
    end
  end

  context "when a dynamic URL has a literal SQLite scheme" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/database.yml").write(<<~YAML)
        production:
          url: sqlite3:<%= ENV.fetch("SQLITE_PATH") %>
      YAML
    end

    it "fails instead of generating a Postgres scaffold" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        expect { Cpflow::Cli.start([described_class::NAME]) }
          .to raise_error(Cpflow::Error, /must be literal file paths/)
        expect(controlplane_config_file_path).not_to exist
      end
    end
  end

  context "when a production SQLite path is outside /app" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/database.yml").write(<<~YAML)
        production:
          primary:
            adapter: sqlite3
            database: /db/production.sqlite3
          cache:
            adapter: sqlite3
            database: /app/db/production.sqlite3
          queue:
            adapter: sqlite3
            database: ../data/production_queue.sqlite3
      YAML
    end

    it "rejects the path before colliding persistent targets" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        expect { Cpflow::Cli.start([described_class::NAME]) }
          .to raise_error(Cpflow::Error, %r{must resolve under /app})
        expect(controlplane_config_file_path).not_to exist
      end
    end

    it "rejects relative traversal outside /app" do
      GENERATOR_PLAYGROUND_PATH.join("config/database.yml").write(<<~YAML)
        production:
          adapter: sqlite3
          database: ../data/production.sqlite3
      YAML

      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        expect { Cpflow::Cli.start([described_class::NAME]) }
          .to raise_error(Cpflow::Error, %r{must resolve under /app})
        expect(controlplane_config_file_path).not_to exist
      end
    end
  end

  context "when production SQLite paths collide after persistence redirection" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/database.yml").write(<<~YAML)
        production:
          primary:
            adapter: sqlite3
            database: db/cache.sqlite3
          cache:
            adapter: sqlite3
            database: data/db/cache.sqlite3
      YAML
    end

    it "rejects the paths before aliasing distinct database connections" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        expect { Cpflow::Cli.start([described_class::NAME]) }
          .to raise_error(Cpflow::Error, /resolve to the same persistent target/)
        expect(controlplane_config_file_path).not_to exist
      end
    end

    it "rejects a legacy fallback that aliases an already-persistent database" do
      GENERATOR_PLAYGROUND_PATH.join("config/database.yml").write(<<~YAML)
        production:
          primary:
            adapter: sqlite3
            database: db/shared.sqlite3
          cache:
            adapter: sqlite3
            database: data/shared.sqlite3
      YAML

      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        expect { Cpflow::Cli.start([described_class::NAME]) }
          .to raise_error(Cpflow::Error, /resolve to the same persistent target/)
        expect(controlplane_config_file_path).not_to exist
      end
    end
  end

  context "when a production SQLite target is an ancestor of another target" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/database.yml").write(<<~YAML)
        production:
          primary:
            adapter: sqlite3
            database: db/cache.sqlite3
          cache:
            adapter: sqlite3
            database: data/db/cache.sqlite3/queue.sqlite3
      YAML
    end

    it "rejects the file-versus-directory conflict" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        expect { Cpflow::Cli.start([described_class::NAME]) }
          .to raise_error(Cpflow::Error, /persistence targets .* overlap/)
        expect(controlplane_config_file_path).not_to exist
      end
    end
  end

  context "when production uses in-memory sqlite3" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/database.yml").write(<<~YAML)
        production:
          adapter: sqlite3
          database: ":memory:"
      YAML
    end

    it "preserves in-memory semantics without a filesystem redirect" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        Cpflow::Cli.start([described_class::NAME])

        expect(entrypoint_path.read).not_to include("prepare_sqlite_database ")
        expect(rails_template_path.read).to include("path: /app/data")
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

  context "when production uses a dynamic URL with an inherited sqlite3 adapter" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/database.yml").write(<<~YAML)
        default: &default
          adapter: sqlite3
          pool: 5
          timeout: 5000

        production:
          <<: *default
          url: <%= ENV.fetch("DATABASE_URL") %>
      YAML
    end

    it "fails instead of guessing a different runtime adapter" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        expect { Cpflow::Cli.start([described_class::NAME]) }
          .to raise_error(Cpflow::Error, /must be literal file paths/)
        expect(controlplane_config_file_path).not_to exist
      end
    end
  end

  context "when production uses sqlite3 in a nested database config" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/database.yml").write(<<~YAML)
        production:
          primary:
            adapter: sqlite3
            database: db/production.sqlite3
          cache:
            adapter: sqlite3
            database: db/production_cache.sqlite3
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
        expect(entrypoint_path.read).to include(
          "prepare_sqlite_database /app/db/production.sqlite3 /app/data/db/production.sqlite3 " \
          "/app/data/production.sqlite3"
        )
        expect(entrypoint_path.read).to include(
          "prepare_sqlite_database /app/db/production_cache.sqlite3 " \
          "/app/data/db/production_cache.sqlite3 /app/data/production_cache.sqlite3"
        )
        expect(entrypoint_path.read).not_to include("production_queue.sqlite3")
      end
    end
  end

  context "when production uses sqlite3 URLs in a nested database config" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/database.yml").write(<<~YAML)
        production:
          primary:
            url: sqlite3:db/production.sqlite3
          cache:
            url: sqlite3:db/production_cache.sqlite3
          queue:
            url: sqlite3:file:/app/db/production_queue.sqlite3?mode=rwc
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
        expect(entrypoint_path.read).to include(
          "prepare_sqlite_database /app/db/production.sqlite3 /app/data/db/production.sqlite3 " \
          "/app/data/production.sqlite3"
        )
        expect(entrypoint_path.read).to include(
          "prepare_sqlite_database /app/db/production_cache.sqlite3 " \
          "/app/data/db/production_cache.sqlite3 /app/data/production_cache.sqlite3"
        )
        expect(entrypoint_path.read).to include(
          "prepare_sqlite_database /app/db/production_queue.sqlite3 " \
          "/app/data/db/production_queue.sqlite3 /app/data/production_queue.sqlite3"
        )
      end
    end
  end

  context "when production has a nested database config with a non-sqlite adapter" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/database.yml").write(<<~YAML)
        production:
          primary:
            adapter: postgresql
            database: app_production
          cache:
            adapter: sqlite3
            database: db/production_cache.sqlite3
      YAML
    end

    it "keeps the postgres-backed templates because the primary database is non-sqlite" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        Cpflow::Cli.start([described_class::NAME])

        controlplane_content = controlplane_config_file_path.read

        expect(controlplane_content).to include("- postgres")
        expect(controlplane_content).not_to include("- db")
        expect(controlplane_content).not_to include("- storage")
        expect(postgres_template_path).to exist
        expect(db_template_path).not_to exist
        expect(storage_template_path).not_to exist
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

        expect(dockerfile_content).to include(
          "RUN export SECRET_KEY_BASE=NOT_USED_NON_BLANK && " \
          "bundle exec rake react_on_rails:generate_packs"
        )
        expect(
          dockerfile_content.index(
            "RUN export SECRET_KEY_BASE=NOT_USED_NON_BLANK && " \
            "bundle exec rake react_on_rails:generate_packs"
          )
        ).to be < dockerfile_content.index("rails assets:precompile")
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

        expect(dockerfile_content).not_to include("rake react_on_rails:generate_packs")
        expect(dockerfile_content).not_to include("USER root")
      end
    end
  end

  context "when shakapacker config defines a chained precompile hook" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/shakapacker.yml").write(<<~YAML)
        default: &default
          precompile_hook: "yarn build && bin/rails react_on_rails:generate_packs"
      YAML
    end

    it "exports the placeholder secret for the entire hook chain" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        Cpflow::Cli.start([described_class::NAME])

        expect(dockerfile_path.read).to include(
          "RUN export SECRET_KEY_BASE=NOT_USED_NON_BLANK && " \
          "yarn build && bin/rails react_on_rails:generate_packs"
        )
      end
    end
  end

  context "when shakapacker config defines a folded single-command precompile hook" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/shakapacker.yml").write(<<~YAML)
        default: &default
          precompile_hook: >
            rake react_on_rails:generate_packs
      YAML
    end

    it "emits the folded scalar as a single RUN line ahead of assets:precompile" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        Cpflow::Cli.start([described_class::NAME])

        dockerfile_content = dockerfile_path.read

        expect(dockerfile_content).to include(
          "RUN export SECRET_KEY_BASE=NOT_USED_NON_BLANK && " \
          "bundle exec rake react_on_rails:generate_packs\n"
        )
        expect(
          dockerfile_content.index(
            "RUN export SECRET_KEY_BASE=NOT_USED_NON_BLANK && " \
            "bundle exec rake react_on_rails:generate_packs"
          )
        ).to be < dockerfile_content.index("rails assets:precompile")
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

        expect(dockerfile_path.read).to include(
          "RUN export SECRET_KEY_BASE=NOT_USED_NON_BLANK && " \
          "bundle exec rake react_on_rails:generate_packs"
        )
      end
    end
  end

  context "when React on Rails auto bundle generation is commented out" do
    before do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config/initializers"))
      GENERATOR_PLAYGROUND_PATH.join("config/initializers/react_on_rails.rb").write(<<~RUBY)
        ReactOnRails.configure do |config|
          # config.auto_load_bundle = true
        end
      RUBY
    end

    it "does not add the React on Rails pack generation step" do
      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        Cpflow::Cli.start([described_class::NAME])

        expect(dockerfile_path.read).not_to include("bundle exec rake react_on_rails:generate_packs")
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

  context "when a root .dockerignore already exists" do
    it "preserves project-specific entries and adds production database exclusions" do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/database.yml").write(<<~YAML)
        production:
          adapter: sqlite3
          database: data/archive/production.sqlite3
      YAML
      dockerignore_path.write("custom-entry\n")

      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        Cpflow::Cli.start([described_class::NAME])
      end

      expect(dockerignore_path.read).to include("custom-entry\n")
      expect(dockerignore_path.read).to include("config/master.key\n")
      expect(dockerignore_path.read).to include("config/credentials/*.key\n")
      expect(dockerignore_path.read).to include("/data/archive/production.sqlite3\n")
      expect(dockerignore_path.read).to include("/data/archive/production.sqlite3-wal\n")
      expect(dockerignore_path.read).to include("/data/archive/production.sqlite3-shm\n")
      expect(dockerignore_path.read).to include("/data/archive/production.sqlite3-journal\n")
    end

    it "escapes pattern metacharacters in production database exclusions" do
      FileUtils.mkdir_p(GENERATOR_PLAYGROUND_PATH.join("config"))
      GENERATOR_PLAYGROUND_PATH.join("config/database.yml").write(<<~YAML)
        production:
          adapter: sqlite3
          database: db/prod[1]*?.sqlite3
      YAML

      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        Cpflow::Cli.start([described_class::NAME])
      end

      expect(dockerignore_path.read).to include('/db/prod\[1\]\*\?.sqlite3')
    end

    it "re-appends the environment exception after a newly added exclusion" do
      dockerignore_path.write("!.env.example\ncustom-entry\n")

      inside_dir(GENERATOR_PLAYGROUND_PATH) do
        Cpflow::Cli.start([described_class::NAME])
      end

      lines = dockerignore_path.readlines(chomp: true)
      expect(lines.rindex("!.env.example")).to be > lines.rindex(".env*")
    end
  end
end
