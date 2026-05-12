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
end
