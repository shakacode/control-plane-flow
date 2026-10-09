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

    it "publishes an unreleased current version instead of bumping past it" do
      Dir.mktmpdir do |root|
        write_file(root, "CHANGELOG.md", changelog("## [4.2.0] - 2026-05-05"))
        write_file(root, "lib/cpflow/version.rb", version_file("4.2.1"))

        expect(described_class.resolve_version_input("", gem_root: root, released_versions: %w[4.1.1 4.2.0]))
          .to eq("4.2.1")
        expect(described_class.resolve_version_input("", gem_root: root, released_versions: %w[4.2.0 4.2.1]))
          .to eq("patch")
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

    describe ".tag_and_push_release!" do
      it "tags the pushed commit and pushes only the release tag" do
        with_release_repo(version: "4.2.0") do |checkout|
          head = git(checkout, "rev-parse", "HEAD")
          git(checkout, "tag", "v0.0.1-scratch")

          described_class.tag_and_push_release!(gem_root: checkout, version: "4.2.0", branch: "main")

          expect(remote_tags(checkout)).to eq(["v4.2.0"])
          expect(git(checkout, "rev-parse", "v4.2.0^{commit}")).to eq(head)
        end
      end

      it "refuses a local release tag that points at another commit" do
        with_release_repo(version: "4.2.0") do |checkout|
          git(checkout, "tag", "v4.2.0")
          commit_file(checkout, "notes.txt", "merged", "Merged bump")
          git(checkout, "push", "-q", "origin", "main")

          expect do
            described_class.tag_and_push_release!(gem_root: checkout, version: "4.2.0", branch: "main")
          end.to raise_error(SystemExit, /git tag -d v4\.2\.0/)
          expect(remote_tags(checkout)).to be_empty
        end
      end

      it "does not tag a commit that is missing from the remote branch" do
        with_release_repo(version: "4.2.0") do |checkout|
          commit_file(checkout, "notes.txt", "local", "Unpushed commit")

          expect do
            described_class.tag_and_push_release!(gem_root: checkout, version: "4.2.0", branch: "main")
          end.to raise_error(SystemExit, %r{not the tip of origin/main})
          expect(git(checkout, "tag", "-l", "v4.2.0")).to eq("")
        end
      end
    end

    describe ".open_version_bump_pull_request!" do
      before do
        allow(described_class).to receive(:apply_version_bump!) do |gem_root:, **|
          write_file(gem_root, "lib/cpflow/version.rb", version_file("4.2.0"))
          write_file(gem_root, "Gemfile.lock", "cpflow (4.2.0)\n")
          write_file(gem_root, "docs/commands.md", "cpflow 4.2.0\n")
        end
        allow(described_class).to receive(:create_version_bump_pull_request!)
      end

      it "pushes the bump to a release branch and leaves the release checkout untouched" do
        with_release_repo do |checkout|
          head = git(checkout, "rev-parse", "HEAD")

          described_class.open_version_bump_pull_request!(
            gem_root: checkout, version_input: "4.2.0", target_gem_version: "4.2.0", base_branch: "main"
          )

          expect(git(checkout, "rev-parse", "HEAD")).to eq(head)
          expect(git(checkout, "status", "--porcelain")).to eq("")
          expect(git(checkout, "tag", "-l")).to eq("")
          expect(git(checkout, "show", "origin/release/v4.2.0:lib/cpflow/version.rb")).to include('"4.2.0"')
          expect(git(checkout, "show", "--stat", "--format=%s", "origin/release/v4.2.0"))
            .to include("Bump version to 4.2.0", "docs/commands.md")
          expect(described_class).to have_received(:create_version_bump_pull_request!)
            .with(hash_including(branch: "release/v4.2.0", base_branch: "main", version: "4.2.0"))
        end
      end

      it "stops when the release branch already exists" do
        with_release_repo do |checkout|
          git(checkout, "branch", "release/v4.2.0")

          expect do
            described_class.open_version_bump_pull_request!(
              gem_root: checkout, version_input: "4.2.0", target_gem_version: "4.2.0", base_branch: "main"
            )
          end.to raise_error(SystemExit, %r{release/v4\.2\.0 already exists})
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
