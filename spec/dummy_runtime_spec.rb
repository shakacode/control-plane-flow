# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Dummy app runtime" do # rubocop:disable RSpec/DescribeClass
  let(:dummy_dir) { File.expand_path("dummy", __dir__) }
  let(:dockerfile) { File.read(File.join(dummy_dir, ".controlplane/Dockerfile")) }
  let(:ruby_version) { File.read(File.join(dummy_dir, ".ruby-version")).strip.delete_prefix("ruby-") }

  it "keeps the Docker image and Bundler Ruby declarations aligned" do
    expect(dockerfile).to include("ARG RUBY_VERSION=#{ruby_version}\n")
    expect(File.read(File.join(dummy_dir, "Gemfile"))).to include("ruby \"#{ruby_version}\"")
    expect(File.read(File.join(dummy_dir, "Gemfile.lock"))).to match(
      /RUBY VERSION\n\s+ruby #{Regexp.escape(ruby_version)}p\d+\n/
    )
  end

  it "uses Bookworm instead of the retired Bullseye package repositories" do
    expect(dockerfile).to include("FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim-bookworm as base")
  end
end
