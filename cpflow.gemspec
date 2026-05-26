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
  spec.post_install_message = <<~MESSAGE
    cpflow #{Cpflow::VERSION} installed.

    If this repository already uses generated cpflow GitHub Actions, update the
    checked-in wrappers so GitHub loads the matching control-plane-flow release tag:

      cpflow update-github-actions
      bin/test-cpflow-github-flow

    If you run cpflow through Bundler:

      bundle exec cpflow update-github-actions
      bin/test-cpflow-github-flow bundle exec cpflow

    New repository? Run `cpflow generate-github-actions` first to create the
    wrappers (and the `bin/test-cpflow-github-flow` script referenced above).
  MESSAGE

  spec.required_ruby_version = ">= 3.0.0"

  spec.add_dependency "dotenv",   "~> 3.1"
  spec.add_dependency "jwt",      "~> 3.1"
  spec.add_dependency "psych",    "~> 5.2"
  spec.add_dependency "thor",     "~> 1.3"

  spec.files = `git ls-files -z`.split("\x0").reject do |file|
    file.match(%r{^(coverage|pkg|spec|tmp)/})
  end

  spec.executables = ["cpflow"]

  spec.metadata["rubygems_mfa_required"] = "true"
end
