# frozen_string_literal: true

require "tmpdir"
require "rake"

previous_rake_application = Rake.application
Rake.application = Rake::Application.new
Rake.application.rake_require("create_release", [File.expand_path("../../rakelib", __dir__)])
Rake.application = previous_rake_application

RSpec.describe Release do
  def write_file(root, path, content)
    full_path = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end

  def changelog(*sections)
    <<~MARKDOWN
      # Changelog

      ## [Unreleased]

      Pending changes.

      #{sections.join("\n\n")}
    MARKDOWN
  end

  def version_file(version)
    <<~RUBY
      # frozen_string_literal: true

      module Cpflow
        VERSION = "#{version}"
      end
    RUBY
  end

  describe ".extract_latest_changelog_version" do
    it "reads the first released CHANGELOG.md version and skips Unreleased" do
      Dir.mktmpdir do |root|
        write_file(root, "CHANGELOG.md", changelog("## [4.2.0] - 2026-05-05", "## [4.1.1] - 2025-03-14"))

        expect(described_class.extract_latest_changelog_version(gem_root: root)).to eq("4.2.0")
      end
    end
  end

  describe ".extract_changelog_section" do
    it "extracts the notes for the requested version header" do
      Dir.mktmpdir do |root|
        write_file(root, "CHANGELOG.md", changelog(<<~MARKDOWN, "## [4.1.1] - 2025-03-14"))
          ## [4.2.0] - 2026-05-05

          ### Added

          - Added the gem-only release flow.
        MARKDOWN

        expect(described_class.extract_changelog_section(gem_root: root, version: "4.2.0")).to eq(<<~MARKDOWN.strip)
          ### Added

          - Added the gem-only release flow.
        MARKDOWN
      end
    end
  end

  describe ".resolve_version_input" do
    it "uses the changelog version when it is newer than the current gem version" do
      Dir.mktmpdir do |root|
        write_file(root, "CHANGELOG.md", changelog("## [4.2.0] - 2026-05-05"))
        write_file(root, "lib/cpflow/version.rb", version_file("4.1.1"))

        expect(described_class.resolve_version_input("", gem_root: root)).to eq("4.2.0")
      end
    end
  end
end
