# frozen_string_literal: true

require_relative "lib/cpl/version"

Gem::Specification.new do |spec|
  spec.name    = "cpl"
  spec.version = Cpl::VERSION
  spec.authors = ["Justin Gordon", "Sergey Tarasov"]
  spec.email   = ["justin@shakacode.com", "sergey@shakacode.com"]

  spec.summary     = "Heroku to Control Plane"
  spec.description = "CLI for providing Heroku-like platform-as-a-service on Control Plane"
  spec.homepage    = "https://github.com/shakacode/control-plane-flow"
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 2.7.0"

  spec.add_dependency "debug",    "~> 1.7.1"
  spec.add_dependency "dotenv",   "~> 2.8.1"
  spec.add_dependency "jwt",      "~> 2.8.1"
  spec.add_dependency "psych",    "~> 5.1.0"
  spec.add_dependency "thor",     "~> 1.2.1"

  spec.add_development_dependency "overcommit",    "~> 0.60.0"
  spec.add_development_dependency "rspec",         "~> 3.12.0"
  spec.add_development_dependency "rspec-retry",   "~> 0.6.2"
  spec.add_development_dependency "rubocop",       "~> 1.45.0"
  spec.add_development_dependency "rubocop-rake",  "~> 0.6.0"
  spec.add_development_dependency "rubocop-rspec", "~> 2.18.1"
  spec.add_development_dependency "simplecov",     "~> 0.22.0"
  spec.add_development_dependency "timecop",       "~> 0.9.6"
  spec.add_development_dependency "webmock",       "~> 3.18.1"

  spec.files = `git ls-files -z`.split("\x0").reject do |file|
    file.match(%r{^(coverage|pkg|spec|tmp)/})
  end

  spec.executables = ["cpl"]

  spec.metadata["rubygems_mfa_required"] = "true"

  spec.post_install_message = "DEPRECATED: The `cpl` gem has been renamed to `cpflow` " \
                              "and will no longer be supported. " \
                              "Please switch to `shakaflow` as soon as possible."
end
