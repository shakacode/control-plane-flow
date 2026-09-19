# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe RepoIntrospection do
  describe ".sqlite_database_in_production?" do
    it "ignores incidental hash-valued production options when every database connection uses sqlite" do
      Dir.mktmpdir("cpflow-repo-introspection") do |root|
        config_dir = File.join(root, "config")
        FileUtils.mkdir_p(config_dir)
        File.write(
          File.join(config_dir, "database.yml"),
          <<~YAML
            production:
              primary:
                adapter: sqlite3
                database: db/production.sqlite3
              cache:
                adapter: sqlite3
                database: db/production_cache.sqlite3
              connected_to_all_handlers:
                strategy: any_replica
          YAML
        )

        expect(described_class.sqlite_database_in_production?(root)).to be(true)
      end
    end

    it "keeps a dynamic URL with an explicit SQLite adapter in the SQLite path" do
      Dir.mktmpdir("cpflow-repo-introspection") do |root|
        config_dir = File.join(root, "config")
        FileUtils.mkdir_p(config_dir)
        File.write(
          File.join(config_dir, "database.yml"),
          <<~YAML
            production:
              adapter: sqlite3
              url: <%= ENV.fetch("DATABASE_URL") %>
          YAML
        )

        expect(described_class.sqlite_database_in_production?(root)).to be(true)
        expect(described_class.unresolved_sqlite_database_paths_in_production?(root)).to be(true)
        expect(described_class.dynamic_database_url_in_production?(root)).to be(true)
      end
    end

    it "recognizes a dynamic URL with a literal SQLite scheme" do
      Dir.mktmpdir("cpflow-repo-introspection") do |root|
        config_dir = File.join(root, "config")
        FileUtils.mkdir_p(config_dir)
        File.write(
          File.join(config_dir, "database.yml"),
          <<~YAML
            production:
              url: sqlite3:<%= ENV.fetch("SQLITE_PATH") %>
          YAML
        )

        expect(described_class.sqlite_database_in_production?(root)).to be(true)
        expect(described_class.unresolved_sqlite_database_paths_in_production?(root)).to be(true)
        expect(described_class.dynamic_database_url_in_production?(root)).to be(false)
      end
    end

    it "recognizes an unknown dynamic URL with literal query options" do
      Dir.mktmpdir("cpflow-repo-introspection") do |root|
        config_dir = File.join(root, "config")
        FileUtils.mkdir_p(config_dir)
        File.write(
          File.join(config_dir, "database.yml"),
          <<~YAML
            production:
              adapter: sqlite3
              url: <%= ENV.fetch("DATABASE_URL") %>?pool=5
          YAML
        )

        expect(described_class.dynamic_database_url_in_production?(root)).to be(true)
      end
    end
  end

  describe ".sqlite_database_paths_in_production" do
    it "returns every literal database path from a multi-database SQLite configuration" do
      Dir.mktmpdir("cpflow-repo-introspection") do |root|
        config_dir = File.join(root, "config")
        FileUtils.mkdir_p(config_dir)
        File.write(
          File.join(config_dir, "database.yml"),
          <<~YAML
            production:
              primary:
                adapter: sqlite3
                database: db/production.sqlite3
              cache:
                url: sqlite3:db/production_cache.sqlite3
              queue:
                adapter: sqlite3
                database: storage/production_queue.sqlite3
          YAML
        )

        expect(described_class.sqlite_database_paths_in_production(root)).to eq(
          ["db/production.sqlite3", "db/production_cache.sqlite3", "storage/production_queue.sqlite3"]
        )
      end
    end

    it "omits in-memory SQLite database identifiers" do
      Dir.mktmpdir("cpflow-repo-introspection") do |root|
        config_dir = File.join(root, "config")
        FileUtils.mkdir_p(config_dir)
        File.write(
          File.join(config_dir, "database.yml"),
          <<~YAML
            production:
              primary:
                adapter: sqlite3
                database: ":memory:"
              cache:
                url: sqlite3:file:cache?mode=memory&cache=shared
          YAML
        )

        expect(described_class.sqlite_database_paths_in_production(root)).to be_empty
      end
    end

    it "prefers a SQLite URL path over the database field like Active Record" do
      Dir.mktmpdir("cpflow-repo-introspection") do |root|
        config_dir = File.join(root, "config")
        FileUtils.mkdir_p(config_dir)
        File.write(
          File.join(config_dir, "database.yml"),
          <<~YAML
            production:
              adapter: sqlite3
              database: db/ignored.sqlite3
              url: sqlite3:db/production.sqlite3
          YAML
        )

        expect(described_class.sqlite_database_paths_in_production(root)).to eq(
          ["db/production.sqlite3"]
        )
      end
    end

    it "decodes percent-encoded SQLite URL paths like Active Record" do
      Dir.mktmpdir("cpflow-repo-introspection") do |root|
        config_dir = File.join(root, "config")
        FileUtils.mkdir_p(config_dir)
        File.write(
          File.join(config_dir, "database.yml"),
          <<~YAML
            production:
              adapter: sqlite3
              url: sqlite3:db/production%20data.sqlite3?pool=5
          YAML
        )

        expect(described_class.sqlite_database_paths_in_production(root)).to eq(
          ["db/production data.sqlite3"]
        )
      end
    end

    it "normalizes SQLite file URIs to their filesystem paths" do
      Dir.mktmpdir("cpflow-repo-introspection") do |root|
        config_dir = File.join(root, "config")
        FileUtils.mkdir_p(config_dir)
        File.write(
          File.join(config_dir, "database.yml"),
          <<~YAML
            production:
              adapter: sqlite3
              url: sqlite3:file:/app/db/production%20data.sqlite3?mode=rwc
          YAML
        )

        expect(described_class.sqlite_database_paths_in_production(root)).to eq(
          ["/app/db/production data.sqlite3"]
        )
      end
    end

    it "uses the path rather than the authority in a SQLite URL" do
      Dir.mktmpdir("cpflow-repo-introspection") do |root|
        config_dir = File.join(root, "config")
        FileUtils.mkdir_p(config_dir)
        File.write(
          File.join(config_dir, "database.yml"),
          <<~YAML
            production:
              adapter: sqlite3
              url: sqlite3://host/db/production.sqlite3
          YAML
        )

        expect(described_class.sqlite_database_paths_in_production(root)).to eq(
          ["/db/production.sqlite3"]
        )
      end
    end
  end

  describe ".unresolved_sqlite_database_paths_in_production?" do
    it "detects ERB-backed production SQLite file paths" do
      Dir.mktmpdir("cpflow-repo-introspection") do |root|
        config_dir = File.join(root, "config")
        FileUtils.mkdir_p(config_dir)
        File.write(
          File.join(config_dir, "database.yml"),
          <<~YAML
            production:
              adapter: sqlite3
              database: <%= ENV.fetch("SQLITE_PATH") %>
          YAML
        )

        expect(described_class.unresolved_sqlite_database_paths_in_production?(root)).to be(true)
      end
    end

    it "accepts in-memory production SQLite databases without file paths" do
      Dir.mktmpdir("cpflow-repo-introspection") do |root|
        config_dir = File.join(root, "config")
        FileUtils.mkdir_p(config_dir)
        File.write(
          File.join(config_dir, "database.yml"),
          <<~YAML
            production:
              adapter: sqlite3
              database: ":memory:"
          YAML
        )

        expect(described_class.unresolved_sqlite_database_paths_in_production?(root)).to be(false)
      end
    end

    it "detects paths containing embedded ERB output" do
      Dir.mktmpdir("cpflow-repo-introspection") do |root|
        config_dir = File.join(root, "config")
        FileUtils.mkdir_p(config_dir)
        File.write(
          File.join(config_dir, "database.yml"),
          <<~YAML
            production:
              adapter: sqlite3
              database: db/<%= Rails.env %>.sqlite3
          YAML
        )

        expect(described_class.unresolved_sqlite_database_paths_in_production?(root)).to be(true)
      end
    end
  end
end
