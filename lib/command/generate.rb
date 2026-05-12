# frozen_string_literal: true

require "yaml"

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

    def copy_files
      generated_paths = copy_template_files("generator_templates", base_template_files)
      generated_paths += copy_template_files("generator_templates_sqlite", SQLITE_TEMPLATE_FILES) if sqlite_project?
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

    def base_template_files
      COMMON_TEMPLATE_FILES + (sqlite_project? ? [] : POSTGRES_TEMPLATE_FILES)
    end

    def template_variables
      {
        "__APP_PREFIX__" => inferred_app_prefix,
        "__RUBY_VERSION__" => inferred_ruby_version,
        "__ASSET_PRECOMPILE_HOOK_RUN__" => asset_precompile_hook_run
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

      "RUN #{stripped}\n\n"
    end

    def single_line_asset_precompile_hook?(command)
      return true unless command.match?(/[\r\n]/)

      Shell.warn("Skipping asset precompile hook: value must be a single line: #{command.inspect}")
      false
    end

    def sqlite_database_in_production?
      RepoIntrospection.sqlite_database_in_production?(Dir.pwd)
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
      config = YAML.safe_load(File.read("config/shakapacker.yml"), aliases: true)
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
