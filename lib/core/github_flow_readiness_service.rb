# frozen_string_literal: true

require "bundler"
require "cgi"
require "net/http"
require "yaml"

require_relative "repo_introspection"
require_relative "github_flow_readiness/checks"

# Drives the readiness checks that gate `cpflow generate-github-actions`. The actual
# checks live in `GithubFlowReadiness::Checks`; this class is the host that owns the
# shared lockfile parser, package.json parser, HTTP version cache, and registry-check
# helpers used across multiple checks. Add a new check by creating a class with `call`
# under `GithubFlowReadiness::Checks` and registering it in `CHECKS`.
class GithubFlowReadinessService # rubocop:disable Metrics/ClassLength
  Result = GithubFlowReadiness::Result
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

  CHECKS = [
    GithubFlowReadiness::Checks::RailsApp,
    GithubFlowReadiness::Checks::RubyVersion,
    GithubFlowReadiness::Checks::BundlerVersion,
    GithubFlowReadiness::Checks::Dockerfile,
    GithubFlowReadiness::Checks::SqliteProduction,
    GithubFlowReadiness::Checks::GemSources,
    GithubFlowReadiness::Checks::GemExactPins,
    GithubFlowReadiness::Checks::NpmExactPins
  ].freeze

  PUBLIC_RUBYGEMS_REMOTE = "https://rubygems.org"
  REGISTRY_FETCH_THREADS = 8
  REGISTRY_FETCH_TIMEOUT_SECONDS = 60

  attr_reader :root_path

  def initialize(root_path: Dir.pwd)
    @root_path = Pathname.new(root_path)
    @package_json_parse_error = false
    @rubygems_versions_cache = build_registry_cache
    @npm_versions_cache = build_registry_cache
  end

  def results
    @results ||= CHECKS.flat_map { |klass| wrap_check_result(klass.new(self).call) }
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

  # ------------------------------------------------------------------
  # Helpers exposed to check classes (and stubbed by specs).
  # ------------------------------------------------------------------

  def gem_dependencies
    @gem_dependencies ||= load_gem_dependencies
  end

  def public_rubygems_dependency?(dependency)
    return false unless dependency[:source_type] == :rubygems

    remotes = dependency[:source_remotes]
    remotes.empty? || remotes.all? { |remote| remote == PUBLIC_RUBYGEMS_REMOTE }
  end

  def inferred_ruby_version
    version_string = RepoIntrospection.inferred_ruby_version_string(root_path.to_s)
    Gem::Version.new(version_string) if version_string
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
    RepoIntrospection.sqlite_database_in_production?(root_path.to_s)
  end

  def parsed_package_json
    return @parsed_package_json if instance_variable_defined?(:@parsed_package_json)

    package_json_path = root_path.join("package.json")
    @package_json_parse_error = false
    return @parsed_package_json = nil unless package_json_path.file?

    @parsed_package_json = JSON.parse(package_json_path.read)
  rescue JSON::ParserError
    @package_json_parse_error = true
    @parsed_package_json = nil
  end

  def package_json_parse_error?
    # `@package_json_parse_error` is set as a side effect of memoizing parsed_package_json;
    # trigger it here so the flag reflects the parse result before we read it.
    parsed_package_json
    @package_json_parse_error
  end

  def package_json_parse_error_result
    Result.new(
      status: :warn,
      message: "Could not parse `package.json`; exact-pinned direct npm package readiness could not be fully verified."
    )
  end

  def rubygems_registry_check
    RegistryCheck.new(
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
    RegistryCheck.new(
      dependencies: exact_npm_dependencies,
      empty_message: "No exact-pinned direct npm packages to verify.",
      missing_prefix: "Direct npm package versions not available on npm",
      unknown_prefix: "Could not verify some exact-pinned npm packages against npm",
      success_noun: "direct npm package",
      availability_proc: method(:npm_dependency_available?),
      registry_name: "npm"
    )
  end

  def exact_pin_registry_result(check)
    return Result.new(status: :info, message: check.empty_message) if check.dependencies.empty?

    grouped = partition_dependencies(check.dependencies, check.availability_proc)
    results = []
    results << registry_unavailable_result(check, grouped[:unavailable]) if grouped[:unavailable].any?
    results << registry_unknown_result(check, grouped[:unknown]) if grouped[:unknown].any?
    return results if results.any?

    Result.new(status: :pass, message: registry_success_message(check))
  end

  # Stubbed in specs; keep public.
  def fetch_rubygems_versions(name)
    fetch_with_cache(rubygems_versions_cache, name) { fetch_versions_from_rubygems(name) }
  end

  # Stubbed in specs; keep public.
  def fetch_npm_versions(name)
    fetch_with_cache(npm_versions_cache, name) { fetch_versions_from_npm(name) }
  end

  private

  attr_reader :rubygems_versions_cache, :npm_versions_cache

  # Wrap a check's return value into an array. Avoid Kernel#Array on a Result Struct,
  # which would unpack it into [status, message] instead of wrapping it.
  def wrap_check_result(value)
    return [] if value.nil?
    return value if value.is_a?(Array)

    [value]
  end

  def build_registry_cache
    { store: {}, mutex: Mutex.new }
  end

  def exact_rubygems_dependencies
    gem_dependencies.select do |dependency|
      public_rubygems_dependency?(dependency) && dependency[:exact_version]
    end
  end

  def exact_npm_dependencies
    package_json = parsed_package_json
    return [] unless package_json

    collect_exact_dependencies(
      package_json.fetch("dependencies", {}),
      package_json.fetch("devDependencies", {})
    )
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
    version.is_a?(String) && version.match?(/\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z/)
  end

  def rubygems_requirement_available?(dependency)
    versions = fetch_rubygems_versions(dependency[:name])
    return nil unless versions

    requirement = dependency[:requirement]
    versions.any? { |version| requirement.satisfied_by?(Gem::Version.new(version)) }
  end

  def npm_dependency_available?(dependency)
    versions = fetch_npm_versions(dependency[:name])
    return nil unless versions

    versions.include?(dependency[:exact_version])
  end

  # Fan out registry lookups across a small thread pool. Each HTTP call has a 5s timeout
  # (see `http_get`), and the join deadline below bounds cases such as DNS resolution
  # hangs that Net::HTTP does not cover. Results are memoized per dependency name;
  # serially this scaled linearly with dependency count, which made readiness slow for
  # repos with many exact pins.
  def partition_dependencies(dependencies, availability_proc)
    results = fetch_availability_in_parallel(dependencies, availability_proc)
    results.each_with_object(unavailable: [], unknown: []) do |(dependency, status), grouped|
      case status
      when false
        grouped[:unavailable] << dependency
      when nil
        grouped[:unknown] << dependency
      end
    end
  end

  def fetch_availability_in_parallel(dependencies, availability_proc)
    initialize_registry_caches
    queue = Queue.new
    indexed = dependencies.each_with_index.to_a
    indexed.each { |entry| queue << entry }
    results = Array.new(dependencies.length)
    result_state = { mutex: Mutex.new, timed_out: false }

    workers = build_availability_workers(queue, availability_proc, results, dependencies.length, result_state)
    wait_for_availability_workers(workers, result_state)
    fill_missing_availability_results(indexed, results)
    results
  end

  def build_availability_workers(queue, availability_proc, results, dependency_count, result_state)
    Array.new([REGISTRY_FETCH_THREADS, dependency_count].min) do
      Thread.new { drain_availability_queue(queue, availability_proc, results, result_state) }
    end
  end

  def initialize_registry_caches
    rubygems_versions_cache
    npm_versions_cache
  end

  def wait_for_availability_workers(workers, result_state)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + REGISTRY_FETCH_TIMEOUT_SECONDS
    workers.each do |worker|
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      worker.join(remaining.positive? ? remaining : 0)
    end
    result_state[:mutex].synchronize { result_state[:timed_out] = true }
  end

  def fill_missing_availability_results(indexed, results)
    indexed.each { |dependency, index| results[index] ||= [dependency, nil] }
  end

  def drain_availability_queue(queue, availability_proc, results, result_state)
    loop do
      break if availability_timed_out?(result_state)

      dependency, index = queue.pop(true)
      write_availability_result(results, index, [dependency, availability_proc.call(dependency)], result_state)
    rescue ThreadError
      break
    end
  end

  def availability_timed_out?(result_state)
    result_state[:mutex].synchronize { result_state[:timed_out] }
  end

  def write_availability_result(results, index, value, result_state)
    result_state[:mutex].synchronize do
      results[index] = value unless result_state[:timed_out]
    end
  end

  # Worker threads in `fetch_availability_in_parallel` may share the cache, so guard
  # both the duplicate-fetch check and the assignment with a mutex. The mutex is released
  # before `yield` so a slow HTTP request does not block other workers from reading cached
  # entries; the trade-off is that N threads racing on a cold cache for the same name can
  # all fire HTTP requests in parallel. That's acceptable here because the fetches are
  # idempotent and the cache is keyed per-name, so duplicates only happen on the first
  # parallel sweep and only for names not yet memoized.
  def fetch_with_cache(cache, name)
    cache[:mutex].synchronize do
      return cache[:store][name] if cache[:store].key?(name)
    end

    value = yield
    cache[:mutex].synchronize { cache[:store][name] = value }
  end

  def fetch_versions_from_rubygems(name)
    uri = URI("https://rubygems.org/api/v1/versions/#{CGI.escape(name)}.json")
    response = http_get(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).map { |entry| entry["number"] }
  rescue JSON::ParserError
    nil
  end

  def fetch_versions_from_npm(name)
    uri = URI("https://registry.npmjs.org/#{npm_package_path_segment(name)}")
    response = http_get(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).fetch("versions", {}).keys
  rescue JSON::ParserError
    nil
  end

  # npm registry expects scoped packages as "@scope%2Fpkg" — leave "@" literal and only encode "/".
  # npm package names are restricted to [a-z0-9._~-@/] so no other path-unsafe chars appear.
  def npm_package_path_segment(name)
    name.gsub("/", "%2F")
  end

  def http_get(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 5
    http.get(uri.request_uri)
  rescue StandardError => e
    warn "github_flow_readiness: HTTP GET #{uri} failed: #{e.class}: #{e.message}" if ENV["CPFLOW_DEBUG"]
    nil
  end

  def load_gem_dependencies
    lockfile_path = root_path.join("Gemfile.lock")
    return [] unless lockfile_path.file?

    parse_gem_dependencies(lockfile_path)
  rescue StandardError => e
    warn "cpflow: failed to parse Gemfile.lock: #{e.class}: #{e.message}" if ENV["CPFLOW_DEBUG"]
    []
  end

  # Parse Gemfile.lock via Bundler::LockfileParser rather than Bundler::Dsl#eval_gemfile.
  # `eval_gemfile` instance_evals the user's Gemfile, which executes arbitrary Ruby. Readiness
  # checks run against untrusted project trees, so we keep the trust boundary at "parse the
  # lockfile only" — no Ruby from the user's repo is ever executed here.
  def parse_gem_dependencies(lockfile_path)
    parser = Bundler::LockfileParser.new(lockfile_path.read)
    parser.dependencies.values.map do |dependency|
      spec = parser.specs.find { |locked_spec| locked_spec.name == dependency.name }
      build_gem_dependency(dependency, source: spec&.source)
    end
  end

  def build_gem_dependency(dependency, source:)
    {
      name: dependency.name,
      exact_version: exact_gem_version(dependency),
      requirement: dependency.requirement,
      source_type: gem_source_type(source),
      source_remotes: gem_source_remotes(source)
    }
  end

  def exact_gem_version(dependency)
    dependency.requirement.requirements.first.last.to_s if dependency.requirement.exact?
  end

  def gem_source_type(source)
    return :rubygems if source.nil? || source.is_a?(Bundler::Source::Rubygems)
    return :path if source.is_a?(Bundler::Source::Path)
    return :git if source.is_a?(Bundler::Source::Git)

    :other
  end

  def gem_source_remotes(source)
    return [] unless source.respond_to?(:remotes)

    Array(source.remotes).map { |remote| normalize_remote(remote) }
  end

  def normalize_remote(remote)
    remote.to_s.sub(%r{/+\z}, "")
  end

  def format_dependencies(dependencies)
    dependencies.map { |dependency| "`#{dependency[:name]}@#{dependency[:exact_version]}`" }.join(", ")
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
