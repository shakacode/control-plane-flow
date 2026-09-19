# frozen_string_literal: true

require "yaml"
require "pathname"
require "shellwords"

require_relative "generator_helpers"
require_relative "../core/repo_introspection"

module Command
  class Generator < Thor::Group # rubocop:disable Metrics/ClassLength
    include Thor::Actions
    include GeneratorHelpers

    COMMON_TEMPLATE_FILES = %w[
      Dockerfile
      entrypoint.sh
    ].freeze
    POSTGRES_TEMPLATE_FILES = %w[
      controlplane.yml
      templates/app.yml
      templates/postgres.yml
      templates/rails.yml
      release_script.sh
    ].freeze
    SQLITE_TEMPLATE_FILES = %w[
      controlplane.yml
      release_script.sh
      templates/app.yml
      templates/db.yml
      templates/rails.yml
      templates/storage.yml
    ].freeze

    # Fallback Ruby version when the repo doesn't pin one via `.ruby-version`,
    # `.tool-versions`, or the `Gemfile`. Keep this on a supported release line
    # (https://www.ruby-lang.org/en/downloads/branches/).
    DEFAULT_RUBY_VERSION = "3.3"
    SQLITE_DATABASE_PREPARE_FUNCTION = <<~SH
      prepare_sqlite_database() {
        source_path="$1"
        persistent_path="$2"
        legacy_path="${3:-}"
        if [ -n "${legacy_path}" ] && [ -e "${legacy_path}" ] && [ ! -e "${persistent_path}" ]; then
          persistent_path="${legacy_path}"
        fi
        mkdir -p "$(dirname "${source_path}")" "$(dirname "${persistent_path}")"
        if [ -e "${source_path}" ] && [ ! -L "${source_path}" ] && [ ! -e "${persistent_path}" ]; then
          mv -n "${source_path}" "${persistent_path}"
        fi
        rm -f "${source_path}"
        ln -s "${persistent_path}" "${source_path}"
      }
    SH

    def copy_files
      validate_sqlite_database_paths!
      generated_paths = copy_template_files("generator_templates", base_template_files)
      generated_paths += copy_template_files("generator_templates_sqlite", SQLITE_TEMPLATE_FILES) if sqlite_project?
      copy_dockerignore unless File.exist?(".dockerignore")
      append_dockerignore_entries
      substitute_template_variables(generated_paths)
      make_shell_scripts_executable(generated_paths)
    end

    def self.source_root
      Cpflow.root_path.join("lib")
    end

    private

    def copy_template_files(root_dir, relative_paths)
      relative_paths.map { |relative_path| copy_template_file(root_dir, relative_path) }
    end

    def copy_template_file(root_dir, relative_path)
      destination_path = File.join(".controlplane", relative_path)
      empty_directory(File.dirname(destination_path), verbose: false)
      copy_file(
        File.join(root_dir, relative_path),
        destination_path,
        force: true,
        verbose: ENV.fetch("HIDE_COMMAND_OUTPUT", nil) != "true"
      )
      destination_path
    end

    def copy_dockerignore
      copy_file(
        File.join("generator_templates", ".dockerignore"),
        ".dockerignore",
        verbose: ENV.fetch("HIDE_COMMAND_OUTPUT", nil) != "true"
      )
    end

    def append_dockerignore_entries
      entries = File.readlines(File.join(self.class.source_root, "generator_templates", ".dockerignore"), chomp: true)
      entries += sqlite_database_ignore_entries if sqlite_project?
      contents = File.read(".dockerignore")
      existing_lines = contents.lines(chomp: true)
      additions = entries - existing_lines
      return if additions.empty?

      File.open(".dockerignore", "a") do |file|
        file.write("\n") unless contents.empty? || contents.end_with?("\n")
        file.puts(additions)
      end
    end

    def sqlite_database_ignore_entries
      RepoIntrospection.sqlite_database_paths_in_production(Dir.pwd).flat_map do |database_path|
        relative = docker_context_database_path(database_path)
        next [] unless relative

        base = "/#{relative}"
        [base, "#{base}-wal", "#{base}-shm", "#{base}-journal"]
      end.uniq
    end

    def docker_context_database_path(database_path)
      path = Pathname.new(database_path).cleanpath
      if path.absolute?
        return unless path.to_s.start_with?("/app/")

        return path.to_s.delete_prefix("/app/")
      end

      normalized = path.to_s
      normalized unless normalized == "." || normalized.start_with?("../")
    end

    def base_template_files
      COMMON_TEMPLATE_FILES + (sqlite_project? ? [] : POSTGRES_TEMPLATE_FILES)
    end

    def template_variables
      {
        "__APP_PREFIX__" => inferred_app_prefix,
        "__RUBY_VERSION__" => inferred_ruby_version,
        "__ASSET_PRECOMPILE_HOOK_RUN__" => asset_precompile_hook_run,
        "__SQLITE_DATABASE_SETUP__" => sqlite_database_setup
      }
    end

    def inferred_app_prefix
      RepoIntrospection.inferred_app_prefix(Dir.pwd)
    end

    def inferred_ruby_version
      RepoIntrospection.inferred_ruby_version_string(Dir.pwd) || DEFAULT_RUBY_VERSION
    end

    def sqlite_project?
      return @sqlite_project if instance_variable_defined?(:@sqlite_project)

      @sqlite_project = sqlite_database_in_production?
    end

    def asset_precompile_hook_run
      command = normalized_asset_precompile_hook_command
      return "" unless command

      # Folded YAML scalars carry a trailing newline even when they hold one command.
      stripped = command.strip
      return "" if stripped.empty?
      return "" unless single_line_asset_precompile_hook?(stripped)

      "RUN export SECRET_KEY_BASE=NOT_USED_NON_BLANK && #{stripped}\n\n"
    end

    def single_line_asset_precompile_hook?(command)
      return true unless command.match?(/[\r\n]/)

      Shell.warn("Skipping asset precompile hook: value must be a single line: #{command.inspect}")
      false
    end

    def sqlite_database_in_production?
      RepoIntrospection.sqlite_database_in_production?(Dir.pwd)
    end

    def validate_sqlite_database_paths!
      return unless sqlite_project?

      validate_sqlite_database_locations!
      return unless RepoIntrospection.unresolved_sqlite_database_paths_in_production?(Dir.pwd)

      raise Cpflow::Error,
            "Production SQLite database paths must be literal file paths in config/database.yml; " \
            "runtime ERB paths cannot be persisted safely by the generated scaffold."
    end

    def validate_sqlite_database_locations!
      unsupported_path = RepoIntrospection.sqlite_database_paths_in_production(Dir.pwd).find do |database_path|
        path = absolute_app_database_path(database_path)
        path != "/app" && !path.start_with?("/app/")
      end
      return unless unsupported_path

      raise Cpflow::Error,
            "Production SQLite database path #{unsupported_path.inspect} must resolve under /app so the generated " \
            "scaffold can persist it safely."
    end

    def sqlite_database_setup
      redirects = sqlite_database_redirects
      return "" if redirects.empty?

      setup_calls = redirects.map do |source, target, legacy|
        arguments = [source, target, legacy].compact.map { |path| Shellwords.shellescape(path) }
        "prepare_sqlite_database #{arguments.join(' ')}"
      end
      "#{SQLITE_DATABASE_PREPARE_FUNCTION}\n#{setup_calls.join("\n")}\n"
    end

    def sqlite_database_redirects
      return [] unless sqlite_project?

      RepoIntrospection.sqlite_database_paths_in_production(Dir.pwd).filter_map do |database_path|
        source = absolute_app_database_path(database_path)
        next if persistent_sqlite_path?(source)

        relative = source.delete_prefix("/")
        target = File.join("/app/data", relative.delete_prefix("app/"))
        [source, target, legacy_sqlite_database_path(source)]
      end
    end

    def legacy_sqlite_database_path(source)
      return unless source.start_with?("/app/db/")

      File.join("/app/data", source.delete_prefix("/app/db/"))
    end

    def absolute_app_database_path(database_path)
      path = Pathname.new(database_path)
      (path.absolute? ? path : Pathname.new("/app").join(path)).cleanpath.to_s
    end

    def persistent_sqlite_path?(path)
      path == "/app/data" || path.start_with?("/app/data/") ||
        path == "/app/storage" || path.start_with?("/app/storage/")
    end

    def normalized_asset_precompile_hook_command
      command = shakapacker_precompile_hook || react_on_rails_auto_bundle_hook
      return unless command

      command.start_with?("rake ") ? "bundle exec #{command}" : command
    end

    def shakapacker_precompile_hook
      return unless File.file?("config/shakapacker.yml")

      # Parse rather than regex-match: Shakapacker emits an environment-keyed YAML file
      # (the hook usually lives under `default:` or `production:`), and folded or quoted
      # multi-line values would also defeat a single-line regex.
      config = YAML.safe_load_file("config/shakapacker.yml", aliases: true)
      hook = extract_shakapacker_precompile_hook(config)
      hook unless hook.nil? || hook.empty?
    rescue Psych::SyntaxError
      nil
    end

    SHAKAPACKER_HOOK_SCOPES = %w[production default].freeze
    private_constant :SHAKAPACKER_HOOK_SCOPES

    def extract_shakapacker_precompile_hook(config)
      return nil unless config.is_a?(Hash)

      scoped = SHAKAPACKER_HOOK_SCOPES.filter_map do |key|
        section = config[key]
        section["precompile_hook"] if section.is_a?(Hash) && section["precompile_hook"].is_a?(String)
      end.first
      scoped || (config["precompile_hook"] if config["precompile_hook"].is_a?(String))
    end

    def react_on_rails_auto_bundle_hook
      return unless react_on_rails_auto_load_bundle?

      "bundle exec rake react_on_rails:generate_packs"
    end

    def react_on_rails_auto_load_bundle?
      return false unless File.file?("config/initializers/react_on_rails.rb")

      File.readlines("config/initializers/react_on_rails.rb")
          .reject { |line| line.lstrip.start_with?("#") }
          .any? { |line| line.match?(/config\.auto_load_bundle\s*=\s*true\b/) }
    end
  end

  class Generate < Base
    NAME = "generate"
    DESCRIPTION = "Creates base Control Plane config and template files"
    LONG_DESCRIPTION = <<~DESC
      Creates base Control Plane config and template files for a Rails project:
      - infers the app prefix from the current directory and wires staging, review, and production entries
      - infers the Docker base Ruby version from `.ruby-version`, `.tool-versions`, or the app's `Gemfile`
      - preserves repo-defined asset precompile hooks, including React on Rails auto bundle generation
      - detects SQLite in `config/database.yml` and generates persistent `/app/data` and `/app/storage` volume templates without hiding image migrations under `/app/db`
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Creates .controlplane directory with Control Plane config and starter templates
      cpflow generate
      ```
    EX
    WITH_INFO_HEADER = false
    VALIDATIONS = [].freeze
    REQUIRES_STARTUP_CHECKS = false

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
