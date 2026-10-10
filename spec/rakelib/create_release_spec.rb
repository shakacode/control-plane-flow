# frozen_string_literal: true

require "open3"
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

    it "keeps the changelog version authoritative when retrying the current version" do
      Dir.mktmpdir do |root|
        write_file(root, "CHANGELOG.md", changelog("## [6.0.0.rc.0] - 2026-09-06"))
        write_file(root, "lib/cpflow/version.rb", version_file("6.0.0.rc.0"))

        expect(described_class.resolve_version_input("", gem_root: root)).to eq("6.0.0.rc.0")
      end
    end
  end

  describe ".compute_target_gem_version" do
    it "does not implicitly promote a prerelease to stable" do
      expect do
        described_class.compute_target_gem_version(
          current_gem_version: "6.0.0.rc.0",
          version_input: "patch"
        )
      end.to raise_error(SystemExit, /Pass an explicit version instead/)
    end

    it "preserves intentional minor and major keyword bumps from a prerelease" do
      expect(
        described_class.compute_target_gem_version(
          current_gem_version: "6.0.0.rc.0",
          version_input: "minor"
        )
      ).to eq("6.1.0")
      expect(
        described_class.compute_target_gem_version(
          current_gem_version: "6.0.0.rc.0",
          version_input: "major"
        )
      ).to eq("7.0.0")
    end
  end

  describe "git-backed release steps" do
    def git(dir, *args)
      output, status = Open3.capture2e("git", "-C", dir, *args)
      raise "git #{args.join(' ')} failed:\n#{output}" unless status.success?

      output.strip
    end

    def commit_file(dir, path, content, message)
      write_file(dir, path, content)
      git(dir, "add", path)
      git(dir, "commit", "-q", "-m", message)
      git(dir, "rev-parse", "HEAD")
    end

    def clone_with_bare_origin(tmp)
      origin = File.join(tmp, "origin.git")
      checkout = File.join(tmp, "checkout")
      Open3.capture2e("git", "init", "-q", "--bare", "--initial-branch=main", origin)
      Open3.capture2e("git", "clone", "-q", origin, checkout)
      git(checkout, "config", "user.email", "release@example.com")
      git(checkout, "config", "user.name", "Release Spec")
      git(checkout, "checkout", "-q", "-B", "main")
      checkout
    end

    def with_release_repo(version: "4.1.1")
      Dir.mktmpdir do |tmp|
        checkout = clone_with_bare_origin(tmp)
        commit_file(checkout, "lib/cpflow/version.rb", version_file(version), "Initial commit")
        git(checkout, "push", "-q", "-u", "origin", "main")

        yield checkout
      end
    end

    def remote_tags(checkout)
      git(checkout, "ls-remote", "--tags", "--refs", "origin").lines.map { |line| line.split("refs/tags/").last.strip }
    end

    around do |example|
      previous_verbose = RakeFileUtils.verbose_flag
      RakeFileUtils.verbose_flag = false
      example.run
    ensure
      RakeFileUtils.verbose_flag = previous_verbose
    end

    before { allow($stdout).to receive(:puts) }

    describe ".tagged_release_gem_versions" do
      it "reads released versions from the remote and ignores local-only tags" do
        with_release_repo do |checkout|
          git(checkout, "tag", "v4.1.0")
          git(checkout, "push", "-q", "origin", "refs/tags/v4.1.0")
          git(checkout, "tag", "v9.9.9")

          expect(described_class.tagged_release_gem_versions(checkout)).to eq(["4.1.0"])
        end
      end

      it "is not blocked by a local tag that differs from the remote tag" do
        with_release_repo do |checkout|
          git(checkout, "tag", "v4.1.0")
          git(checkout, "push", "-q", "origin", "refs/tags/v4.1.0")
          commit_file(checkout, "notes.txt", "local", "Local only commit")
          git(checkout, "tag", "-f", "v4.1.0")

          expect(described_class.tagged_release_gem_versions(checkout)).to eq(["4.1.0"])
        end
      end
    end

    describe ".commit_tag_and_push!" do
      it "pushes the bump, then tags that commit and pushes only the release tag" do
        with_release_repo do |checkout|
          write_file(checkout, "lib/cpflow/version.rb", version_file("4.2.0"))
          write_file(checkout, "Gemfile.lock", "cpflow (4.2.0)\n")
          write_file(checkout, "docs/commands.md", "cpflow 4.2.0\n")
          git(checkout, "tag", "v0.0.1-scratch")

          described_class.commit_tag_and_push!(gem_root: checkout, version: "4.2.0")

          expect(remote_tags(checkout)).to eq(["v4.2.0"])
          expect(git(checkout, "rev-parse", "v4.2.0^{commit}")).to eq(git(checkout, "rev-parse", "origin/main"))
          expect(git(checkout, "show", "--stat", "--format=%s", "origin/main"))
            .to include("Bump version to 4.2.0", "docs/commands.md")
        end
      end

      it "does not create the tag when the branch push is rejected" do
        with_release_repo do |checkout|
          write_file(checkout, "lib/cpflow/version.rb", version_file("4.2.0"))
          write_file(checkout, "Gemfile.lock", "cpflow (4.2.0)\n")
          write_file(checkout, "docs/commands.md", "cpflow 4.2.0\n")
          git(checkout, "remote", "set-url", "--push", "origin", File.join(checkout, "missing.git"))

          expect { described_class.commit_tag_and_push!(gem_root: checkout, version: "4.2.0") }
            .to raise_error(RuntimeError, /git push/)
          expect(git(checkout, "tag", "-l", "v4.2.0")).to eq("")
        end
      end

      it "refuses a local release tag that points at another commit" do
        with_release_repo(version: "4.2.0") do |checkout|
          git(checkout, "tag", "v4.2.0")
          commit_file(checkout, "notes.txt", "later", "Later commit")
          %w[Gemfile.lock docs/commands.md].each { |path| commit_file(checkout, path, "4.2.0\n", "Add #{path}") }

          expect { described_class.commit_tag_and_push!(gem_root: checkout, version: "4.2.0") }
            .to raise_error(SystemExit, /git tag -d v4\.2\.0/)
          expect(remote_tags(checkout)).to be_empty
        end
      end
    end

    describe ".ensure_git_tag_exists!" do
      it "reports a release tag that is missing from the remote" do
        with_release_repo do |checkout|
          git(checkout, "tag", "v4.2.0")

          expect { described_class.ensure_git_tag_exists!(gem_root: checkout, tag: "v4.2.0") }
            .to raise_error(SystemExit, /was not found on origin/)
        end
      end
    end
  end
end
