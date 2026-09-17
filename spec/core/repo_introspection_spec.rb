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
end
