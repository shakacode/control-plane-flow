# frozen_string_literal: true

require "spec_helper"
require "pathname"
require "tmpdir"

describe GithubFlowReadinessService do
  let(:playground) { Pathname.new(Dir.mktmpdir("cpflow-github-flow-readiness-service")) }
  let(:service) { described_class.new(root_path: playground) }
  let(:ruby_version) { "3.3.7" }

  before do
    FileUtils.mkdir_p(playground.join("config"))
    FileUtils.mkdir_p(playground.join("bin"))
    File.write(playground.join("bin/rails"), "#!/usr/bin/env ruby\n")
    File.write(playground.join("config/application.rb"), "# app\n")
    File.write(playground.join("config.ru"), "run Rails.application\n")
    File.write(playground.join("Dockerfile"), "FROM ruby:3.3.7\n")
    File.write(playground.join(".ruby-version"), "#{ruby_version}\n")
    File.write(playground.join("Gemfile"), gemfile_contents)
    File.write(playground.join("Gemfile.lock"), gemfile_lock_contents)
    File.write(playground.join("package.json"), package_json_contents)
    File.write(playground.join("config/database.yml"), database_yml) if database_yml
  end

  after do
    FileUtils.remove_entry(playground.to_s) if playground.exist?
  end

  def bundler_version
    "2.5.22"
  end

  def database_yml
    nil
  end

  def gemfile_contents
    <<~GEMFILE
      source "https://rubygems.org"
      gem "rails", "8.0.2.1"
      gem "react_on_rails", "= 16.4.0"
    GEMFILE
  end

  def gemfile_lock_contents
    <<~LOCKFILE
      GEM
        remote: https://rubygems.org/
        specs:
          rails (8.0.2.1)
          react_on_rails (16.4.0)

      DEPENDENCIES
        rails (= 8.0.2.1)
        react_on_rails (= 16.4.0)

      BUNDLED WITH
         #{bundler_version}
    LOCKFILE
  end

  def package_json_contents
    JSON.pretty_generate(
      {
        name: "demo-app",
        dependencies: npm_dependencies
      }
    )
  end

  def npm_dependencies
    {
      "react-on-rails" => "16.4.0"
    }
  end

  it "passes for a modern repo when exact pins are available" do
    allow(service).to receive(:fetch_rubygems_versions).with("rails").and_return(["8.0.2.1"])
    allow(service).to receive(:fetch_rubygems_versions).with("react_on_rails").and_return(["16.4.0"])
    allow(service).to receive(:fetch_npm_versions).with("react-on-rails").and_return(["16.4.0"])

    expect(service.blockers?).to be(false)
    expect(service.results.map(&:message)).to include("Ruby 3.3.7 is modern enough for rollout.")
    expect(service.results.map(&:message)).to include(
      "Checked 2 exact-pinned direct Ruby gems; all appear available on RubyGems."
    )
    expect(service.results.map(&:message)).to include(
      "Checked 1 exact-pinned direct npm package; all appear available on npm."
    )
  end

  it "fails when no production Dockerfile is present" do
    File.delete(playground.join("Dockerfile"))

    allow(service).to receive(:fetch_rubygems_versions).with("rails").and_return(["8.0.2.1"])
    allow(service).to receive(:fetch_rubygems_versions).with("react_on_rails").and_return(["16.4.0"])
    allow(service).to receive(:fetch_npm_versions).with("react-on-rails").and_return(["16.4.0"])

    expect(service.blockers?).to be(true)
    expect(service.results.map(&:message)).to include(
      "No production Dockerfile found at `Dockerfile` or `.controlplane/Dockerfile`. " \
      "Add and validate one before generating the Control Plane GitHub flow."
    )
  end

  it "does not execute Ruby from the target Gemfile while checking readiness" do
    sentinel_path = playground.join("gemfile-side-effect.txt")
    File.write(playground.join("Gemfile"), <<~GEMFILE)
      File.write("#{sentinel_path}", "executed")
      source "https://rubygems.org"
      gem "rails", "8.0.2.1"
      gem "react_on_rails", "= 16.4.0"
    GEMFILE

    allow(service).to receive(:fetch_rubygems_versions).with("rails").and_return(["8.0.2.1"])
    allow(service).to receive(:fetch_rubygems_versions).with("react_on_rails").and_return(["16.4.0"])
    allow(service).to receive(:fetch_npm_versions).with("react-on-rails").and_return(["16.4.0"])

    service.results

    expect(sentinel_path).not_to exist
  end

  it "treats exact Ruby gem pins without patch segments as available when RubyGems normalizes them" do
    File.write(playground.join("Gemfile"), <<~GEMFILE)
      source "https://rubygems.org"
      gem "react_on_rails", "= 16.6"
      gem "shakapacker", "= 10.0"
    GEMFILE
    File.write(playground.join("Gemfile.lock"), <<~LOCKFILE)
      GEM
        remote: https://rubygems.org/
        specs:
          react_on_rails (16.6.0)
          shakapacker (10.0.0)

      DEPENDENCIES
        react_on_rails (= 16.6)
        shakapacker (= 10.0)

      BUNDLED WITH
         #{bundler_version}
    LOCKFILE

    allow(service).to receive(:fetch_rubygems_versions).with("react_on_rails").and_return(["16.6.0"])
    allow(service).to receive(:fetch_rubygems_versions).with("shakapacker").and_return(["10.0.0"])
    allow(service).to receive(:fetch_npm_versions).with("react-on-rails").and_return(["16.4.0"])

    expect(service.blockers?).to be(false)
    expect(service.results.map(&:message)).to include(
      "Checked 2 exact-pinned direct Ruby gems; all appear available on RubyGems."
    )
  end

  it "reports legacy toolchains and unavailable direct pins as blockers" do
    File.write(playground.join(".ruby-version"), "2.5.1\n")
    File.write(playground.join("Gemfile"), <<~GEMFILE)
      source "https://rubygems.org"
      gem "react_on_rails", "= 15.0.0"
    GEMFILE
    File.write(playground.join("Gemfile.lock"), <<~LOCKFILE)
      GEM
        remote: https://rubygems.org/
        specs:
          react_on_rails (15.0.0)

      DEPENDENCIES
        react_on_rails (= 15.0.0)

      BUNDLED WITH
         1.12.3
    LOCKFILE
    File.write(
      playground.join("package.json"),
      JSON.pretty_generate(
        {
          name: "demo-app",
          dependencies: {
            "react-on-rails-rsc" => "16.4.0"
          }
        }
      )
    )

    allow(service).to receive(:fetch_rubygems_versions).with("react_on_rails").and_return([])
    allow(service).to receive(:fetch_npm_versions).with("react-on-rails-rsc").and_return([])

    expect(service.blockers?).to be(true)
    expect(service.results.map(&:message)).to include(
      "Ruby 2.5.1 is legacy. Upgrade the repo toolchain before adding the GitHub flow."
    )
    expect(service.results.map(&:message)).to include(
      "Bundler 1.12.3 is legacy. Upgrade the repo toolchain before adding the GitHub flow."
    )
    expect(service.results.map(&:message)).to include(
      "Direct Ruby gem versions not available on RubyGems: `react_on_rails@15.0.0`."
    )
    expect(service.results.map(&:message)).to include(
      "Direct npm package versions not available on npm: `react-on-rails-rsc@16.4.0`."
    )
  end

  it "warns about git-sourced gems and SQLite production" do
    File.write(playground.join("Gemfile"), <<~GEMFILE)
      source "https://rubygems.org"
      gem "rails", "8.0.2.1"
      gem "private-gem", github: "org/private-gem"
    GEMFILE
    File.write(playground.join("Gemfile.lock"), <<~LOCKFILE)
      GIT
        remote: https://github.com/org/private-gem.git
        revision: 1234567890abcdef1234567890abcdef12345678
        specs:
          private-gem (0.1.0)

      GEM
        remote: https://rubygems.org/
        specs:
          rails (8.0.2.1)

      DEPENDENCIES
        private-gem!
        rails (= 8.0.2.1)

      BUNDLED WITH
         #{bundler_version}
    LOCKFILE
    File.write(playground.join("config/database.yml"), <<~YAML)
      default: &default
        adapter: sqlite3

      production:
        <<: *default
        database: db/production.sqlite3
    YAML

    allow(service).to receive(:fetch_rubygems_versions).with("rails").and_return(["8.0.2.1"])
    allow(service).to receive(:fetch_npm_versions).with("react-on-rails").and_return(["16.4.0"])

    expect(service.results.map(&:status)).to include(:warn, :info)
    expect(service.results.map(&:message).join("\n")).to include("git/path or non-public gem sources")
    expect(service.results.map(&:message).join("\n")).to include("Production database config uses SQLite")
  end

  it "warns about direct gems from non-public rubygems sources instead of checking rubygems.org" do
    File.write(playground.join("Gemfile"), <<~GEMFILE)
      source "https://gems.example.com"
      gem "private-gem", "= 1.2.3"
    GEMFILE
    File.write(playground.join("Gemfile.lock"), <<~LOCKFILE)
      GEM
        remote: https://gems.example.com/
        specs:
          private-gem (1.2.3)

      DEPENDENCIES
        private-gem (= 1.2.3)

      BUNDLED WITH
         #{bundler_version}
    LOCKFILE

    allow(service).to receive(:fetch_rubygems_versions)
    allow(service).to receive(:fetch_npm_versions).with("react-on-rails").and_return(["16.4.0"])

    messages = service.results.map(&:message)

    expect(service).not_to have_received(:fetch_rubygems_versions)
    expect(messages.join("\n")).to include("git/path or non-public gem sources")
    expect(messages).not_to include(
      "Checked 1 exact-pinned direct Ruby gem; all appear available on RubyGems."
    )
  end

  it "warns when package.json cannot be parsed" do
    File.write(playground.join("package.json"), "{invalid json\n")
    allow(service).to receive(:fetch_rubygems_versions).with("rails").and_return(["8.0.2.1"])
    allow(service).to receive(:fetch_rubygems_versions).with("react_on_rails").and_return(["16.4.0"])

    expect(service.results.map(&:message)).to include(
      "Could not parse `package.json`; exact-pinned direct npm package readiness could not be fully verified."
    )
  end

  it "treats exact prerelease npm versions as exact pins to verify" do
    File.write(
      playground.join("package.json"),
      JSON.pretty_generate(
        {
          name: "demo-app",
          dependencies: {
            "@demo/widget" => "1.2.3-beta.1"
          }
        }
      )
    )

    allow(service).to receive(:fetch_rubygems_versions).with("rails").and_return(["8.0.2.1"])
    allow(service).to receive(:fetch_rubygems_versions).with("react_on_rails").and_return(["16.4.0"])
    allow(service).to receive(:fetch_npm_versions).with("@demo/widget").and_return(["1.2.3-beta.1"])

    expect(service.results.map(&:message)).to include(
      "Checked 1 exact-pinned direct npm package; all appear available on npm."
    )
  end
end
