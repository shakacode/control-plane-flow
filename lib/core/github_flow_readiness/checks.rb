# frozen_string_literal: true

module GithubFlowReadiness
  Result = Struct.new(:status, :message, keyword_init: true)

  # Each check class accepts the host service in its initializer (so it can reach the
  # shared lockfile parser, HTTP version cache, etc.), exposes a single `call` method,
  # and returns either a `Result`, an array of `Result`s, or `nil` (skipped). Adding
  # a new check is "create a class with `call` and register it in
  # `GithubFlowReadinessService::CHECKS`".
  module Checks
    class Base
      def initialize(service)
        @service = service
      end

      private

      attr_reader :service

      def root_path
        service.root_path
      end

      def pass(message)
        Result.new(status: :pass, message: message)
      end

      def fail_result(message)
        Result.new(status: :fail, message: message)
      end

      def warn_result(message)
        Result.new(status: :warn, message: message)
      end

      def info_result(message)
        Result.new(status: :info, message: message)
      end

      def format_path_list(paths)
        paths.map { |path| "`#{path}`" }.join(", ")
      end

      def first_existing_path(paths)
        paths.find { |relative_path| root_path.join(relative_path).file? }
      end

      def missing_paths_for(paths)
        paths.reject { |relative_path| root_path.join(relative_path).file? }
      end
    end

    class RailsApp < Base
      REQUIRED_PATHS = ["Gemfile", "bin/rails", "config/application.rb", "config.ru"].freeze

      def call
        missing = missing_paths_for(REQUIRED_PATHS)
        return pass("Rails app scaffold found (#{format_path_list(REQUIRED_PATHS)}).") if missing.empty?

        fail_result("Missing Rails runtime scaffold: #{format_path_list(missing)}.")
      end
    end

    class RubyVersion < Base
      # Oldest Ruby line still receiving security backports (ruby-lang.org/en/downloads/branches/).
      # Bump this when the upstream branch list drops a series.
      THRESHOLD = Gem::Version.new("3.1.0")

      def call
        version = service.inferred_ruby_version
        return warn_result("Could not determine the app Ruby version.") unless version
        return pass("Ruby #{version} is modern enough for rollout.") if version >= THRESHOLD

        fail_result("Ruby #{version} is legacy. Upgrade the repo toolchain before adding the GitHub flow.")
      end
    end

    class BundlerVersion < Base
      THRESHOLD = Gem::Version.new("2.0.0")

      def call
        version = service.lockfile_bundler_version
        return warn_result("Could not determine the Bundler version from `Gemfile.lock`.") unless version
        return pass("Bundler #{version} is modern enough for rollout.") if version >= THRESHOLD

        fail_result("Bundler #{version} is legacy. Upgrade the repo toolchain before adding the GitHub flow.")
      end
    end

    class Dockerfile < Base
      PATHS = ["Dockerfile", ".controlplane/Dockerfile"].freeze

      def call
        path = first_existing_path(PATHS)
        return pass("Found production Dockerfile at `#{path}`.") if path

        fail_result(
          "No production Dockerfile found at `Dockerfile` or `.controlplane/Dockerfile`. " \
          "Add and validate one before generating the Control Plane GitHub flow."
        )
      end
    end

    class SqliteProduction < Base
      def call
        return unless service.sqlite_database_in_production?

        info_result(
          "Production database config uses SQLite. `cpflow generate` will scaffold " \
          "persistent `db` and `storage` volumes."
        )
      end
    end

    class GemSources < Base
      def call
        non_public = service.gem_dependencies.reject { |dep| service.public_rubygems_dependency?(dep) }
        return [] if non_public.empty?

        names = non_public.map { |dep| dep[:name] }.sort
        warn_result(
          "Direct Ruby dependencies using git/path or non-public gem sources need manual review: " \
          "#{names.map { |name| "`#{name}`" }.join(', ')}."
        )
      end
    end

    class GemExactPins < Base
      def call
        service.exact_pin_registry_result(service.rubygems_registry_check)
      end
    end

    class NpmExactPins < Base
      def call
        return service.package_json_parse_error_result if service.package_json_parse_error?

        service.exact_pin_registry_result(service.npm_registry_check)
      end
    end
  end
end
