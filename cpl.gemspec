# frozen_string_literal: true

require_relative "lib/cpl/version"

Gem::Specification.new do |spec|
  spec.name    = "cpl"
  spec.version = Cpl::VERSION
  spec.authors = ["Justin Gordon", "Sergey Tarasov"]
  spec.email   = ["justin@shakacode.com", "dzirtusss@gmail.com"]

  spec.summary     = "Heroku to Control Plane"
  spec.description = "Helper CLI for migrating from Heroku to Control Plane"
  spec.homepage    = "https://github.com/shakacode/heroku-to-control-plane"
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 2.7.0"

  spec.add_dependency "cgi",      "~> 0.3.6"
  spec.add_dependency "debug",    "~> 1.7.1"
  spec.add_dependency "dotenv",   "~> 2.8.1"
  spec.add_dependency "json",     "~> 2.6.3"
  spec.add_dependency "net-http", "~> 0.3.2"
  spec.add_dependency "optparse", "~> 0.3.1"
  spec.add_dependency "pathname", "~> 0.2.1"
  spec.add_dependency "tempfile", "~> 0.1.3"
  spec.add_dependency "thor",     "~> 1.2.1"
  spec.add_dependency "yaml",     "~> 0.2.1"

  spec.add_development_dependency "rspec",   "~> 3.12.0"
  spec.add_development_dependency "rubocop", "~> 1.45.0"

  spec.files = `git ls-files`.split("\n")
  spec.executables = ["cpl"]

  spec.metadata["rubygems_mfa_required"] = "true"
end
