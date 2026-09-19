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
      contents = File.read(".dockerignore")
      existing_lines = contents.lines(chomp: true)
      additions = dockerignore_additions(existing_lines)
      return if additions.empty?

      File.open(".dockerignore", "a") do |file|
        file.write("\n") unless contents.empty? || contents.end_with?("\n")
        file.puts(additions)
      end
    end

    def dockerignore_additions(existing_lines)
      entries = File.readlines(File.join(self.class.source_root, "generator_templates", ".dockerignore"), chomp: true)
      sqlite_entries = sqlite_project? ? sqlite_database_ignore_entries : []
      entries += sqlite_entries
      env_entries = [".env*", "!.env.example"]
      mandatory_exclusions = ["config/master.key", "config/credentials/*.key", *sqlite_entries]
      ordinary_entries = entries - env_entries - mandatory_exclusions
      additions = ordinary_entries - existing_lines
      additions += mandatory_exclusions.reject { |entry| dockerignore_exclusion_effective?(existing_lines, entry) }
      additions += env_entries unless dockerignore_env_exception_preserved?(existing_lines)
      additions
    end

    def dockerignore_exclusion_effective?(lines, exclusion)
      exclusion_index = lines.rindex(exclusion)
      exclusion_index && lines[(exclusion_index + 1)..].none? { |line| line.start_with?("!") }
    end

    def dockerignore_env_exception_preserved?(lines)
      exclusion_index = lines.rindex(".env*")
      exception_index = lines.rindex("!.env.example")
      return false unless exclusion_index && exception_index && exception_index > exclusion_index

      lines[(exception_index + 1)..].none? { |line| line.start_with?("!") }
    end

    def sqlite_database_ignore_entries
      RepoIntrospection.sqlite_database_paths_in_production(Dir.pwd).flat_map do |database_path|
        relative = docker_context_database_path(database_path)
        next [] unless relative

        base = "/#{escape_dockerignore_path(relative)}"
        [base, "#{base}-wal", "#{base}-shm", "#{base}-journal"]
      end.uniq
    end

    def escape_dockerignore_path(path)
      path.gsub(/[\\*?\[\]]/) { |character| "\\#{character}" }
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
      validate_sqlite_persistence_targets!
      return unless RepoIntrospection.unresolved_sqlite_database_paths_in_production?(Dir.pwd)

      raise Cpflow::Error,
            "Production SQLite database paths must be literal file paths in config/database.yml; " \
            "runtime ERB paths cannot be persisted safely by the generated scaffold."
    end

    def validate_sqlite_database_locations!
      database_paths = RepoIntrospection.sqlite_database_paths_in_production(Dir.pwd)
      validate_sqlite_paths_under_app!(database_paths)
      validate_sqlite_paths_below_mount_roots!(database_paths)
    end

    def validate_sqlite_paths_under_app!(database_paths)
      unsupported_path = database_paths.find do |database_path|
        path = absolute_app_database_path(database_path)
        path != "/app" && !path.start_with?("/app/")
      end
      return unless unsupported_path

      raise Cpflow::Error,
            "Production SQLite database path #{unsupported_path.inspect} must resolve under /app so the generated " \
            "scaffold can persist it safely."
    end

    def validate_sqlite_paths_below_mount_roots!(database_paths)
      mount_root_path = database_paths.find do |database_path|
        ["/app/data", "/app/storage"].include?(absolute_app_database_path(database_path))
      end
      return unless mount_root_path

      raise Cpflow::Error,
            "Production SQLite database path #{mount_root_path.inspect} resolves to a volume mount directory; " \
            "use a file path beneath data/ or storage/."
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

        target = persistent_sqlite_target(source)
        [source, target, legacy_sqlite_database_path(source)]
      end
    end

    def validate_sqlite_persistence_targets!
      paths_by_target = sqlite_database_paths_by_persistence_target
      validate_exact_sqlite_target_collisions!(paths_by_target)
      validate_ancestor_sqlite_target_collisions!(paths_by_target.keys)
    end

    def validate_exact_sqlite_target_collisions!(paths_by_target)
      collision = paths_by_target.find { |_target, paths| paths.uniq.size > 1 }
      return unless collision

      target = collision.first
      paths = collision.last.uniq
      raise Cpflow::Error,
            "Production SQLite database paths #{paths.map(&:inspect).join(' and ')} resolve to the same persistent " \
            "target #{target.inspect}; use distinct paths before generating the scaffold."
    end

    def validate_ancestor_sqlite_target_collisions!(targets)
      collision = targets.combination(2).find do |first, second|
        sqlite_path_ancestor?(first, second) || sqlite_path_ancestor?(second, first)
      end
      return unless collision

      first, second = collision
      raise Cpflow::Error,
            "Production SQLite persistence targets #{first.inspect} and #{second.inspect} overlap; " \
            "a database file cannot contain another database path."
    end

    def sqlite_path_ancestor?(ancestor, descendant)
      descendant.start_with?("#{ancestor}/")
    end

    def sqlite_database_paths_by_persistence_target
      paths_by_target = Hash.new { |hash, key| hash[key] = [] }
      RepoIntrospection.sqlite_database_paths_in_production(Dir.pwd).each do |database_path|
        source = absolute_app_database_path(database_path)
        target = persistent_sqlite_path?(source) ? source : persistent_sqlite_target(source)
        [target, legacy_sqlite_database_path(source)].compact.each do |claimed_path|
          paths_by_target[claimed_path] << database_path
        end
      end
      paths_by_target
    end

    def persistent_sqlite_target(source)
      relative = source.delete_prefix("/")
      File.join("/app/data", relative.delete_prefix("app/"))
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
