# frozen_string_literal: true

require "yaml"

module RepoIntrospection
  DEFAULT_APP_PREFIX = "my-app"

  # Pure string → version-string extractor. Strips a leading `ruby-` prefix and returns
  # the first `MAJOR.MINOR[.PATCH]` found in the source, or nil.
  def self.parse_ruby_version_string(source)
    normalized = source.strip.sub(/\Aruby-/, "")
    normalized[/\d+\.\d+(?:\.\d+)?/]
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

  # Returns true if `config/database.yml` under `root` configures SQLite for production
  # (either directly or via `<<: *default`). ERB in the YAML is stubbed before parsing.
  def self.sqlite_database_in_production?(root)
    path = File.join(root, "config/database.yml")
    return false unless File.file?(path)

    parsed = safe_load_database_yml(File.read(path))
    return false unless parsed.is_a?(Hash)

    production = parsed["production"]
    return false unless production.is_a?(Hash)

    sqlite_adapter_in_hash?(production) || sqlite_adapter_in_hash?(parsed["default"])
  end

  def self.safe_load_database_yml(raw_contents)
    stubbed = raw_contents.gsub(/<%=.*?%>/m, "__erb__").gsub(/<%.*?%>/m, "")
    YAML.safe_load(stubbed, aliases: true, permitted_classes: [Symbol])
  rescue Psych::SyntaxError
    nil
  end

  def self.sqlite_adapter_in_hash?(config)
    return false unless config.is_a?(Hash)

    adapter = config["adapter"]
    adapter.is_a?(String) && adapter.strip.start_with?("sqlite3")
  end
end
