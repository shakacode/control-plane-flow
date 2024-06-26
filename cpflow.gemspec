# frozen_string_literal: true

require_relative "lib/cpflow/version"

Gem::Specification.new do |spec|
  spec.name    = "cpflow"
  spec.version = Cpflow::VERSION
  spec.authors = ["Justin Gordon", "Sergey Tarasov"]
  spec.email   = ["justin@shakacode.com", "sergey@shakacode.com"]

  spec.summary     = "Control Plane Flow"
  spec.description = "CLI for providing Heroku-like platform-as-a-service on Control Plane"
  spec.homepage    = "https://github.com/shakacode/control-plane-flow"
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 2.7.0"

  spec.add_dependency "dotenv",   "~> 2.8.1"
  spec.add_dependency "jwt",      "~> 2.8.1"
  spec.add_dependency "psych",    "~> 5.1.0"
  spec.add_dependency "thor",     "~> 1.2.1"

  spec.files = `git ls-files -z`.split("\x0").reject do |file|
    file.match(%r{^(coverage|pkg|spec|tmp)/})
  end

  spec.executables = ["cpflow"]

  spec.metadata["rubygems_mfa_required"] = "true"
end
