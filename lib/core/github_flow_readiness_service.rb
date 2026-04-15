# frozen_string_literal: true

require "bundler"
require "cgi"

class GithubFlowReadinessService # rubocop:disable Metrics/ClassLength
  Result = Struct.new(:status, :message, keyword_init: true)
  RegistryCheck = Struct.new(
    :dependencies,
    :empty_message,
    :missing_prefix,
    :unknown_prefix,
    :success_noun,
    :availability_proc,
    :registry_name,
    keyword_init: true
  )

  LEGACY_RUBY_VERSION = Gem::Version.new("3.0.0")
  LEGACY_BUNDLER_VERSION = Gem::Version.new("2.0.0")
  REQUIRED_RAILS_PATHS = ["Gemfile", "config/application.rb", "config.ru"].freeze
  DOCKERFILE_PATHS = ["Dockerfile", ".controlplane/Dockerfile"].freeze

  attr_reader :root_path

  def initialize(root_path: Dir.pwd)
    @root_path = Pathname.new(root_path)
  end

  def results
    @results ||= build_results
  end

  def blockers?
    results.any? { |result| result.status == :fail }
  end

  def summary
    if blockers?
      "Blockers found. Fix them before generating the Control Plane GitHub flow."
    else
      "No blocking readiness issues detected. Validate the real production build path before merging."
    end
  end

  private

  def build_results
    [
      rails_app_result,
      ruby_version_result,
      bundler_version_result,
      dockerfile_result,
      sqlite_result,
      *gem_source_results,
      gem_exact_pin_result,
      npm_exact_pin_result
    ].compact
  end

  def rails_app_result
    missing_paths = missing_paths_for(REQUIRED_RAILS_PATHS)
    return rails_app_present_result if missing_paths.empty?

    Result.new(status: :fail, message: "Missing Rails runtime scaffold: #{format_path_list(missing_paths)}.")
  end

  def ruby_version_result
    toolchain_version_result(
      version: inferred_ruby_version,
      threshold: LEGACY_RUBY_VERSION,
      missing_message: "Could not determine the app Ruby version.",
      ok_message: ->(version) { "Ruby #{version} is modern enough for rollout." },
      fail_message: lambda do |version|
        "Ruby #{version} is legacy. Upgrade the repo toolchain before adding the GitHub flow."
      end
    )
  end

  def bundler_version_result
    toolchain_version_result(
      version: lockfile_bundler_version,
      threshold: LEGACY_BUNDLER_VERSION,
      missing_message: "Could not determine the Bundler version from `Gemfile.lock`.",
      ok_message: ->(version) { "Bundler #{version} is modern enough for rollout." },
      fail_message: lambda do |version|
        "Bundler #{version} is legacy. Upgrade the repo toolchain before adding the GitHub flow."
      end
    )
  end

  def dockerfile_result
    dockerfile_path = first_existing_path(DOCKERFILE_PATHS)
    return dockerfile_present_result(dockerfile_path) if dockerfile_path

    missing_dockerfile_result
  end

  def sqlite_result
    return unless sqlite_database_in_production?

    Result.new(
      status: :info,
      message: "Production database config uses SQLite. `cpflow generate` will scaffold " \
               "persistent `db` and `storage` volumes."
    )
  end

  def gem_source_results
    non_rubygems_dependencies = gem_dependencies.reject { |dependency| dependency[:source_type] == :rubygems }
    return [] if non_rubygems_dependencies.empty?

    names = non_rubygems_dependencies.map { |dependency| dependency[:name] }.sort

    [
      Result.new(
        status: :warn,
        message: "Direct Ruby dependencies using git/path or non-RubyGems sources need manual review: " \
                 "#{names.map { |name| "`#{name}`" }.join(', ')}."
      )
    ]
  end

  def gem_exact_pin_result
    exact_pin_registry_result(rubygems_registry_check)
  end

  def npm_exact_pin_result
    exact_pin_registry_result(npm_registry_check)
  end

  def gem_dependencies
    @gem_dependencies ||= load_gem_dependencies
  end

  def gem_source_type(source)
    return :rubygems if source.nil? || source.is_a?(Bundler::Source::Rubygems)
    return :path if source.is_a?(Bundler::Source::Path)
    return :git if source.is_a?(Bundler::Source::Git)

    :other
  end

  def exact_npm_dependencies
    package_json = parsed_package_json
    return [] unless package_json

    collect_exact_dependencies(
      package_json.fetch("dependencies", {}),
      package_json.fetch("devDependencies", {})
    )
  end

  def inferred_ruby_version
    ruby_version_from_ruby_version_file ||
      ruby_version_from_tool_versions ||
      ruby_version_from_gemfile
  end

  def ruby_version_from_ruby_version_file
    file_path = root_path.join(".ruby-version")
    return unless file_path.file?

    parse_ruby_version(file_path.read)
  end

  def ruby_version_from_tool_versions
    file_path = root_path.join(".tool-versions")
    return unless file_path.file?

    ruby_line = file_path.readlines(chomp: true).find { |line| line.match?(/^\s*ruby\s+/) }
    return unless ruby_line

    parse_ruby_version(ruby_line.sub(/^\s*ruby\s+/, ""))
  end

  def ruby_version_from_gemfile
    file_path = root_path.join("Gemfile")
    return unless file_path.file?

    ruby_line = file_path.readlines(chomp: true).find { |line| line.match?(/^\s*ruby\s+/) }
    return unless ruby_line

    parse_ruby_version(ruby_line.sub(/^\s*ruby\s+/, ""))
  end

  def parse_ruby_version(source)
    normalized_source = source.strip.sub(/\Aruby-/, "")
    version = normalized_source[/\d+\.\d+(?:\.\d+)?/]
    return unless version

    Gem::Version.new(version)
  end

  def lockfile_bundler_version
    file_path = root_path.join("Gemfile.lock")
    return unless file_path.file?

    lines = file_path.readlines(chomp: true)
    bundler_index = lines.index("BUNDLED WITH")
    return unless bundler_index

    version = lines[(bundler_index + 1)..]&.find { |line| !line.strip.empty? }&.strip
    return unless version

    Gem::Version.new(version)
  end

  def sqlite_database_in_production?
    file_path = root_path.join("config/database.yml")
    return false unless file_path.file?

    database_config = file_path.read
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

  def rubygems_requirement_available?(dependency)
    versions = fetch_rubygems_versions(dependency[:name])
    return nil unless versions

    requirement = dependency[:requirement]
    versions.any? { |version| requirement.satisfied_by?(Gem::Version.new(version)) }
  end

  def npm_version_available?(name, version)
    versions = fetch_npm_versions(name)
    return nil unless versions

    versions.include?(version)
  end

  def fetch_rubygems_versions(name)
    @rubygems_versions ||= {}
    @rubygems_versions[name] ||= begin
      uri = URI("https://rubygems.org/api/v1/versions/#{CGI.escape(name)}.json")
      response = http_get(uri)
      return unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body).map { |entry| entry["number"] }
    rescue JSON::ParserError
      nil
    end
  end

  def fetch_npm_versions(name)
    @npm_versions ||= {}
    @npm_versions[name] ||= begin
      uri = URI("https://registry.npmjs.org/#{CGI.escape(name)}")
      response = http_get(uri)
      return unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body).fetch("versions", {}).keys
    rescue JSON::ParserError
      nil
    end
  end

  def http_get(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 5
    http.get(uri.request_uri)
  rescue StandardError
    nil
  end

  def format_dependencies(dependencies)
    dependencies.map { |dependency| "`#{dependency[:name]}@#{dependency[:exact_version]}`" }.join(", ")
  end

  def format_path_list(paths)
    paths.map { |path| "`#{path}`" }.join(", ")
  end

  def missing_paths_for(paths)
    paths.reject { |relative_path| root_path.join(relative_path).file? }
  end

  def first_existing_path(paths)
    paths.find { |relative_path| root_path.join(relative_path).file? }
  end

  def rails_app_present_result
    Result.new(status: :pass, message: "Rails app scaffold found (#{format_path_list(REQUIRED_RAILS_PATHS)}).")
  end

  def dockerfile_present_result(dockerfile_path)
    Result.new(status: :pass, message: "Found production Dockerfile at `#{dockerfile_path}`.")
  end

  def missing_dockerfile_result
    Result.new(
      status: :warn,
      message: "No production Dockerfile found at `Dockerfile` or `.controlplane/Dockerfile`. " \
               "`cpflow generate` can scaffold one, but you still need to validate a real production build."
    )
  end

  def toolchain_version_result(version:, threshold:, missing_message:, ok_message:, fail_message:)
    return Result.new(status: :warn, message: missing_message) unless version
    return Result.new(status: :pass, message: ok_message.call(version)) if version >= threshold

    Result.new(status: :fail, message: fail_message.call(version))
  end

  def load_gem_dependencies
    gemfile_path = root_path.join("Gemfile")
    return [] unless gemfile_path.file?

    parse_gem_dependencies(gemfile_path)
  rescue StandardError
    []
  end

  def parse_gem_dependencies(gemfile_path)
    dsl = Bundler::Dsl.new
    dsl.eval_gemfile(gemfile_path.to_s)
    dsl.dependencies.map { |dependency| build_gem_dependency(dependency) }
  end

  def build_gem_dependency(dependency)
    {
      name: dependency.name,
      exact_version: exact_gem_version(dependency),
      requirement: dependency.requirement,
      source_type: gem_source_type(dependency.source)
    }
  end

  def exact_gem_version(dependency)
    dependency.requirement.requirements.first.last.to_s if dependency.requirement.exact?
  end

  def exact_rubygems_dependencies
    gem_dependencies.select do |dependency|
      dependency[:source_type] == :rubygems && dependency[:exact_version]
    end
  end

  def parsed_package_json
    package_json_path = root_path.join("package.json")
    return unless package_json_path.file?

    JSON.parse(package_json_path.read)
  rescue JSON::ParserError
    nil
  end

  def collect_exact_dependencies(*dependency_sets)
    dependency_sets.flat_map { |dependencies| exact_dependency_entries(dependencies) }
  end

  def exact_dependency_entries(dependencies)
    dependencies.filter_map do |name, version|
      { name: name, exact_version: version } if exact_version_string?(version)
    end
  end

  def exact_version_string?(version)
    version.is_a?(String) && version.match?(/\A\d+\.\d+\.\d+\z/)
  end

  def rubygems_registry_check
    build_registry_check(
      dependencies: exact_rubygems_dependencies,
      empty_message: "No exact-pinned direct Ruby gems to verify.",
      missing_prefix: "Direct Ruby gem versions not available on RubyGems",
      unknown_prefix: "Could not verify some exact-pinned Ruby gems against RubyGems",
      success_noun: "direct Ruby gem",
      availability_proc: method(:rubygems_requirement_available?),
      registry_name: "RubyGems"
    )
  end

  def npm_registry_check
    build_registry_check(
      dependencies: exact_npm_dependencies,
      empty_message: "No exact-pinned direct npm packages to verify.",
      missing_prefix: "Direct npm package versions not available on npm",
      unknown_prefix: "Could not verify some exact-pinned npm packages against npm",
      success_noun: "direct npm package",
      availability_proc: method(:npm_dependency_available?),
      registry_name: "npm"
    )
  end

  def build_registry_check(**attributes)
    RegistryCheck.new(**attributes)
  end

  def npm_dependency_available?(dependency)
    npm_version_available?(dependency[:name], dependency[:exact_version])
  end

  def exact_pin_registry_result(check)
    return Result.new(status: :info, message: check.empty_message) if check.dependencies.empty?

    grouped_dependencies = partition_dependencies(check.dependencies, check.availability_proc)
    unavailable_dependencies = grouped_dependencies.fetch(:unavailable)
    unknown_dependencies = grouped_dependencies.fetch(:unknown)
    return registry_unavailable_result(check, unavailable_dependencies) if unavailable_dependencies.any?
    return registry_unknown_result(check, unknown_dependencies) if unknown_dependencies.any?

    Result.new(status: :pass, message: registry_success_message(check))
  end

  def partition_dependencies(dependencies, availability_proc)
    dependencies.each_with_object(unavailable: [], unknown: []) do |dependency, grouped_dependencies|
      case availability_proc.call(dependency)
      when false
        grouped_dependencies[:unavailable] << dependency
      when nil
        grouped_dependencies[:unknown] << dependency
      end
    end
  end

  def registry_success_message(check)
    dependency_count = check.dependencies.length
    noun = "#{check.success_noun}#{'s' if dependency_count != 1}"

    "Checked #{dependency_count} exact-pinned #{noun}; all appear available on #{check.registry_name}."
  end

  def registry_unavailable_result(check, dependencies)
    Result.new(status: :fail, message: "#{check.missing_prefix}: #{format_dependencies(dependencies)}.")
  end

  def registry_unknown_result(check, dependencies)
    Result.new(status: :warn, message: "#{check.unknown_prefix}: #{format_dependencies(dependencies)}.")
  end
end
