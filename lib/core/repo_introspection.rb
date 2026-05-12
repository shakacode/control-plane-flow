# frozen_string_literal: true

require "yaml"

module RepoIntrospection
  DEFAULT_APP_PREFIX = "my-app"
  RUBY_VERSION_DIRECTIVE_PATTERN = /^\s*ruby\s+['"\d]/
  RUBY_VERSION_DIRECTIVE_PREFIX = /^\s*ruby\s+/

  # Pure string → version-string extractor. Strips a leading `ruby-` prefix and returns
  # the first `MAJOR.MINOR[.PATCH]` found in the source, or nil.
  def self.parse_ruby_version_string(source)
    normalized = source.strip.sub(/\Aruby-/, "")
    normalized[/\d+\.\d+(?:\.\d+)?/]
  end

  # Returns the first Ruby version string the repo declares, checked in the order Bundler
  # itself uses: `.ruby-version`, then `.tool-versions`, then `Gemfile`. Returns nil when
  # no source declares a version. Both `Command::Generator` and `GithubFlowReadinessService`
  # call into this so a future format change (e.g. `.tool-versions`) only updates here.
  def self.inferred_ruby_version_string(root)
    ruby_version_from_ruby_version_file(root) ||
      ruby_version_from_tool_versions(root) ||
      ruby_version_from_gemfile(root)
  end

  def self.ruby_version_from_ruby_version_file(root)
    path = File.join(root, ".ruby-version")
    return unless File.file?(path)

    parse_ruby_version_string(File.read(path))
  end

  def self.ruby_version_from_tool_versions(root)
    path = File.join(root, ".tool-versions")
    return unless File.file?(path)

    ruby_line = File.readlines(path, chomp: true).find { |line| line.match?(RUBY_VERSION_DIRECTIVE_PREFIX) }
    return unless ruby_line

    parse_ruby_version_string(ruby_line.sub(RUBY_VERSION_DIRECTIVE_PREFIX, ""))
  end

  def self.ruby_version_from_gemfile(root)
    path = File.join(root, "Gemfile")
    return unless File.file?(path)

    ruby_lines = File.readlines(path, chomp: true).select { |line| line.match?(RUBY_VERSION_DIRECTIVE_PREFIX) }
    ruby_line = ruby_lines.find { |line| line.match?(RUBY_VERSION_DIRECTIVE_PATTERN) }
    warn_dynamic_ruby_directive if ruby_lines.any? && ruby_line.nil?
    return unless ruby_line

    parse_ruby_version_string(ruby_line.sub(RUBY_VERSION_DIRECTIVE_PREFIX, ""))
  end

  def self.warn_dynamic_ruby_directive
    return unless ENV["CPFLOW_DEBUG"]

    warn "cpflow: Gemfile has a dynamic `ruby` directive; falling back to the default Ruby version"
  end

  # Returns a Control Plane-safe app prefix derived from the basename of `root`:
  # lower-cased, with non-alphanumeric runs collapsed to dashes and stripped from
  # the ends. Falls back to DEFAULT_APP_PREFIX when the result is empty.
  def self.inferred_app_prefix(root)
    sanitized = File.basename(root)
                    .downcase
                    .gsub(/[^a-z0-9]+/, "-")
                    .gsub(/\A-+|-+\z/, "")

    sanitized.empty? ? DEFAULT_APP_PREFIX : sanitized
  end

  # Returns true if `config/database.yml` under `root` configures SQLite for production.
  # YAML merge keys such as `<<: *default` are resolved by safe_load, so only the
  # final production hash should be inspected.
  def self.sqlite_database_in_production?(root)
    path = File.join(root, "config/database.yml")
    return false unless File.file?(path)

    parsed = safe_load_database_yml(File.read(path))
    return false unless parsed.is_a?(Hash)

    production = parsed["production"]
    return false unless production.is_a?(Hash)

    sqlite_database_config?(production)
  end

  # Recursively determines whether a database config hash uses SQLite. Handles both
  # the single-database shape (top-level `adapter`/`url`) and Rails 6.1+ multi-database
  # shape where each connection sits one level deeper (`primary:`, `cache:`, etc.).
  # Returns false on any explicit non-SQLite adapter so a mixed config (e.g. Postgres
  # primary + SQLite cache) keeps the Postgres scaffold rather than a volume scaffold.
  def self.sqlite_database_config?(config)
    return false unless config.is_a?(Hash)

    direct_result = direct_sqlite_database_config?(config)
    return direct_result unless direct_result.nil?

    nested_sqlite_database_config?(config)
  end

  # Returns true/false when a direct `url` or `adapter` key is conclusive, or nil
  # when neither key is present so the caller can check nested sub-configs.
  def self.direct_sqlite_database_config?(config)
    url = config["url"]
    return sqlite_database_url?(url) if url.is_a?(String) && !url.strip.empty?

    return sqlite_adapter_in_hash?(config) if config["adapter"].is_a?(String)

    nil
  end

  def self.nested_sqlite_database_config?(config)
    # In Rails multi-database configs, hash values at this level are named
    # connections such as primary:, cache:, or queue:. Scalar keys are ignored.
    sub_configs = config.values.select { |value| value.is_a?(Hash) }
    return false if sub_configs.empty?

    sub_configs.all? { |sub| sqlite_database_config?(sub) }
  end

  def self.safe_load_database_yml(raw_contents)
    # ERB conditionals can change YAML structure, so avoid guessing. Output-only
    # ERB is stubbed as a scalar so common Rails defaults like `pool: <%= ... %>`
    # still parse, but control-flow ERB returns unknown. `<%- ... %>` is a
    # whitespace-trimming code tag, not an output tag, so treat it as unknown too.
    # Callers treat unknown as non-SQLite and
    # emit the default Postgres scaffold rather than guessing wrong.
    return nil if raw_contents.match?(/<%(?![=#])/m)

    stubbed = raw_contents.gsub(/<%=.*?%>/m, "__erb__").gsub(/<%#.*?%>/m, "")
    YAML.safe_load(stubbed, aliases: true, permitted_classes: [Symbol])
  rescue Psych::SyntaxError
    nil
  end

  def self.sqlite_adapter_in_hash?(config)
    return false unless config.is_a?(Hash)

    adapter = config["adapter"]
    adapter.is_a?(String) && adapter.strip.start_with?("sqlite3")
  end

  def self.sqlite_database_url?(url)
    url.strip.downcase.start_with?("sqlite:", "sqlite3:")
  end
end
