# frozen_string_literal: true

module Command
  class Generator < Thor::Group # rubocop:disable Metrics/ClassLength
    include Thor::Actions

    BASE_TEMPLATE_FILES = %w[
      Dockerfile
      controlplane.yml
      entrypoint.sh
      release_script.sh
      templates/app.yml
      templates/rails.yml
    ].freeze
    POSTGRES_TEMPLATE_FILES = %w[templates/postgres.yml].freeze
    SQLITE_TEMPLATE_FILES = %w[
      controlplane.yml
      release_script.sh
      templates/app.yml
      templates/db.yml
      templates/rails.yml
      templates/storage.yml
    ].freeze

    DEFAULT_APP_PREFIX = "my-app"
    DEFAULT_RUBY_VERSION = "3.1.2"

    def copy_files
      copy_template_files("generator_templates", base_template_files)
      copy_template_files("generator_templates_sqlite", SQLITE_TEMPLATE_FILES) if sqlite_project?
      substitute_template_variables(".controlplane")
      make_shell_scripts_executable(".controlplane")
    end

    def self.source_root
      Cpflow.root_path.join("lib")
    end

    private

    def copy_template_files(root_dir, relative_paths)
      relative_paths.each do |relative_path|
        destination_path = File.join(".controlplane", relative_path)
        empty_directory(File.dirname(destination_path), verbose: false)
        copy_file(
          File.join(root_dir, relative_path),
          destination_path,
          force: true,
          verbose: ENV.fetch("HIDE_COMMAND_OUTPUT", nil) != "true"
        )
      end
    end

    def base_template_files
      sqlite_project? ? BASE_TEMPLATE_FILES : BASE_TEMPLATE_FILES + POSTGRES_TEMPLATE_FILES
    end

    def substitute_template_variables(root_path)
      Dir.glob(File.join(root_path, "**/*")).each do |path|
        next unless File.file?(path)

        contents = File.read(path)
        updated_contents = template_variables.reduce(contents) do |memo, (placeholder, value)|
          memo.gsub(placeholder, value)
        end

        next if updated_contents == contents

        File.write(path, updated_contents)
      end
    end

    def template_variables
      {
        "__APP_PREFIX__" => inferred_app_prefix,
        "__RUBY_VERSION__" => inferred_ruby_version
      }
    end

    def inferred_app_prefix
      sanitized_dirname = File.basename(Dir.pwd)
                              .downcase
                              .gsub(/[^a-z0-9]+/, "-")
                              .gsub(/\A-+|-+\z/, "")

      sanitized_dirname.empty? ? DEFAULT_APP_PREFIX : sanitized_dirname
    end

    def inferred_ruby_version
      ruby_version_from_ruby_version_file ||
        ruby_version_from_tool_versions ||
        ruby_version_from_gemfile ||
        DEFAULT_RUBY_VERSION
    end

    def sqlite_project?
      @sqlite_project ||= sqlite_database_in_production?
    end

    def ruby_version_from_ruby_version_file
      return unless File.file?(".ruby-version")

      parse_ruby_version(File.read(".ruby-version"))
    end

    def ruby_version_from_tool_versions
      return unless File.file?(".tool-versions")

      ruby_line = File.readlines(".tool-versions", chomp: true).find { |line| line.match?(/^\s*ruby\s+/) }
      return unless ruby_line

      parse_ruby_version(ruby_line.sub(/^\s*ruby\s+/, ""))
    end

    def ruby_version_from_gemfile
      return unless File.file?("Gemfile")

      ruby_line = File.readlines("Gemfile", chomp: true).find { |line| line.match?(/^\s*ruby\s+/) }
      return unless ruby_line

      parse_ruby_version(ruby_line.sub(/^\s*ruby\s+/, ""))
    end

    def parse_ruby_version(source)
      normalized_source = source.strip.sub(/\Aruby-/, "")
      normalized_source[/\d+\.\d+(?:\.\d+)?/]
    end

    def sqlite_database_in_production?
      return false unless File.file?("config/database.yml")

      database_config = File.read("config/database.yml")
      production_block = top_level_yaml_block(database_config, "production")
      default_block = top_level_yaml_block(database_config, "default")

      sqlite_adapter?(production_block) ||
        (inherits_default_config?(production_block) && sqlite_adapter?(default_block))
    end

    def top_level_yaml_block(database_config, section_name)
      lines = database_config.lines
      start_index = lines.index { |line| line.match?(/^#{Regexp.escape(section_name)}:/) }
      return unless start_index

      block_lines = [lines[start_index]]
      lines[(start_index + 1)..]&.each do |line|
        break if line.match?(/^\S/)

        block_lines << line
      end

      block_lines.join
    end

    def sqlite_adapter?(yaml_block)
      yaml_block&.match?(/^\s*adapter:\s*sqlite3\b/)
    end

    def inherits_default_config?(yaml_block)
      yaml_block&.match?(/^\s*<<:\s*\*default\b/)
    end

    def make_shell_scripts_executable(root_path)
      Dir.glob(File.join(root_path, "**/*.sh")).each do |path|
        next unless File.file?(path)

        FileUtils.chmod(0o755, path)
      end
    end
  end

  class Generate < Base
    NAME = "generate"
    DESCRIPTION = "Creates base Control Plane config and template files"
    LONG_DESCRIPTION = <<~DESC
      Creates base Control Plane config and template files for a Rails project:
      - infers the app prefix from the current directory and wires staging, review, and production entries
      - infers the Docker base Ruby version from `.ruby-version`, `.tool-versions`, or the app's `Gemfile`
      - detects SQLite in `config/database.yml` and generates persistent `db` and `storage` volume templates instead of the default Postgres workload
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Creates .controlplane directory with Control Plane config and starter templates
      cpflow generate
      ```
    EX
    WITH_INFO_HEADER = false
    VALIDATIONS = [].freeze

    def call
      if controlplane_directory_exists?
        Shell.warn("The directory '.controlplane' already exists!")
        return
      end

      Generator.start
    end

    private

    def controlplane_directory_exists?
      Dir.exist? ".controlplane"
    end
  end
end
