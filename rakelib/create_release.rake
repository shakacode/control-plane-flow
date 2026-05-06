# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength, Metrics/ClassLength, Metrics/CyclomaticComplexity
# rubocop:disable Metrics/MethodLength, Metrics/ModuleLength, Metrics/PerceivedComplexity

require "bundler"
require "English"
require "fileutils"
require "open3"
require "rubygems/version"
require "shellwords"
require "tempfile"
require "tmpdir"

Rake::Task[:release].clear if Rake::Task.task_defined?(:release)

desc("Releases the cpflow Ruby gem.

  The recommended flow is changelog-first:
    1. Merge the CHANGELOG.md update for the target version.
    2. Run `bundle exec rake release`.
    3. Enter the RubyGems OTP when prompted.

  With no version argument, the task reads the latest versioned CHANGELOG.md
  header and uses it when it is newer than the current gem version. Otherwise,
  it falls back to a patch bump.

  1st argument: Version (optional). Supported values:
                patch, minor, major, 4.2.0, or 4.2.0.rc.1
  2nd argument: Dry run (true/false, default: false)
  3rd argument: Override version policy checks (true/false, default: false)

  Environment variables:
    VERBOSE=1
    RUBYGEMS_OTP=<code>
    RELEASE_VERSION_POLICY_OVERRIDE=true
    GEM_RELEASE_MAX_RETRIES=<n>

  Examples:
    bundle exec rake release
    bundle exec rake \"release[patch]\"
    bundle exec rake \"release[4.2.0]\"
    bundle exec rake \"release[4.2.0.rc.1]\"
    bundle exec rake \"release[4.2.0,true]\"")
task :release, %i[version dry_run override_version_policy] do |_t, args|
  args_hash = args.to_hash
  gem_root = Release.gem_root
  is_dry_run = Release.object_to_boolean(args_hash[:dry_run])
  allow_version_policy_override = Release.version_policy_override_enabled?(args_hash[:override_version_policy])
  rubygems_otp = ENV.fetch("RUBYGEMS_OTP", nil)
  current_branch = Release.current_git_branch(gem_root)
  released_gem_version = nil

  Release.ensure_there_is_nothing_to_commit(gem_root)
  Release.run_release_preflight_checks!(gem_root: gem_root, dry_run: is_dry_run)

  Release.with_release_checkout(gem_root: gem_root, dry_run: is_dry_run) do |release_root|
    Release.update_the_local_project(release_root) unless is_dry_run

    version_input = Release.resolve_version_input(args_hash.fetch(:version, ""), gem_root: release_root)
    Release.validate_requested_version_input!(version_input)

    current_checkout_version = Release.current_gem_version(release_root)
    target_gem_version = Release.compute_target_gem_version(
      current_gem_version: current_checkout_version,
      version_input: version_input
    )

    Release.ensure_release_branch_allowed!(
      current_branch: current_branch,
      target_gem_version: target_gem_version
    )

    Release.validate_release_version_policy!(
      gem_root: release_root,
      target_gem_version: target_gem_version,
      allow_override: allow_version_policy_override,
      fetch_tags: true
    )

    Release.confirm_release!(version: target_gem_version, gem_root: release_root) unless is_dry_run
    Release.bump_gem_version!(gem_root: release_root, version_input: version_input)
    Release.update_lockfile!(gem_root: release_root)

    released_gem_version = Release.current_gem_version(release_root)

    next if is_dry_run

    Release.commit_tag_and_push!(gem_root: release_root, version: released_gem_version)
    Release.publish_gem_with_retry(release_root, "cpflow", otp: rubygems_otp)
  end

  if is_dry_run
    puts ""
    puts "DRY RUN COMPLETE"
    puts "Version would be bumped to: #{released_gem_version}"
    puts "To release for real, run: bundle exec rake \"release[#{released_gem_version}]\""
  else
    Release.sync_github_release_after_publish(gem_root: gem_root, gem_version: released_gem_version, dry_run: false)
    puts ""
    puts "RELEASE COMPLETE"
    puts "Published cpflow #{released_gem_version} to RubyGems.org."
  end
end

desc("Compatibility alias for the old release task. Prefer `bundle exec rake release`.")
task :create_release, %i[gem_version dry_run] do |_t, args|
  args_hash = args.to_hash
  Rake::Task[:release].invoke(args_hash.fetch(:gem_version, ""), args_hash[:dry_run])
end

desc("Creates or updates the GitHub release notes from CHANGELOG.md.

  1st argument: Gem version in RubyGems format, e.g. 4.2.0 or 4.2.0.rc.1
  2nd argument: Dry run (true/false, default: false)

  Examples:
    bundle exec rake \"sync_github_release[4.2.0]\"
    bundle exec rake \"sync_github_release[4.2.0.rc.1]\"
    bundle exec rake \"sync_github_release[4.2.0,true]\"")
task :sync_github_release, %i[gem_version dry_run] do |_t, args|
  args_hash = args.to_hash
  gem_root = Release.gem_root
  is_dry_run = Release.object_to_boolean(args_hash[:dry_run])
  requested_gem_version = args_hash[:gem_version].to_s.strip

  if requested_gem_version.empty?
    abort "gem_version is required. Usage: bundle exec rake \"sync_github_release[4.2.0]\""
  end

  Release.validate_requested_version_input!(requested_gem_version)

  if is_dry_run
    if Release.changelog_dirty?(gem_root: gem_root)
      abort "DRY RUN: CHANGELOG.md has uncommitted changes. Commit or stash it before syncing."
    end
  else
    Release.ensure_changelog_committed!(gem_root: gem_root)
  end

  Release.verify_gh_auth(gem_root: gem_root)
  release_context = Release.prepare_github_release_context(gem_root: gem_root, gem_version: requested_gem_version)
  Release.publish_or_update_github_release(gem_root: gem_root, release_context: release_context, dry_run: is_dry_run)
end

module Release
  extend FileUtils
  extend Rake::FileUtilsExt if defined?(Rake::FileUtilsExt)

  PRERELEASE_PATTERN = /\.(test|beta|alpha|rc|pre)\./i
  VERSION_PATTERN = /\A\d+\.\d+\.\d+(\.(test|beta|alpha|rc|pre)\.\d+)?\z/i

  class << self
    def gem_root
      File.expand_path("..", __dir__)
    end

    def object_to_boolean(value)
      [true, "true", "yes", 1, "1", "t"].include?(value.instance_of?(String) ? value.downcase : value)
    end

    def version_policy_override_enabled?(override_flag)
      object_to_boolean(override_flag) || object_to_boolean(ENV.fetch("RELEASE_VERSION_POLICY_OVERRIDE", nil))
    end

    def semver_keyword?(value)
      %w[patch minor major].include?(value.to_s.strip.downcase)
    end

    def prerelease_version?(version)
      version.to_s.match?(PRERELEASE_PATTERN)
    end

    def validate_requested_version_input!(version_input)
      return if semver_keyword?(version_input)
      return if version_input.to_s.match?(VERSION_PATTERN)

      abort <<~ERROR
        Invalid version argument: #{version_input.inspect}

        Use:
          - patch, minor, or major
          - explicit version: 4.2.0
          - explicit prerelease: 4.2.0.rc.1
      ERROR
    end

    def parse_gem_version_components(gem_version)
      match = gem_version.to_s.strip.match(/\A(\d+)\.(\d+)\.(\d+)(?:\.(test|beta|alpha|rc|pre)\.(\d+))?\z/i)
      abort "Unsupported gem version format: #{gem_version.inspect}" unless match

      {
        major: match[1].to_i,
        minor: match[2].to_i,
        patch: match[3].to_i,
        prerelease_type: match[4]&.downcase,
        prerelease_index: match[5]&.to_i
      }
    end

    def compute_target_gem_version(current_gem_version:, version_input:)
      return version_input unless semver_keyword?(version_input)

      version = parse_gem_version_components(current_gem_version)

      case version_input.to_s.strip.downcase
      when "patch"
        return "#{version[:major]}.#{version[:minor]}.#{version[:patch]}" if version[:prerelease_type]

        "#{version[:major]}.#{version[:minor]}.#{version[:patch] + 1}"
      when "minor"
        "#{version[:major]}.#{version[:minor] + 1}.0"
      when "major"
        "#{version[:major] + 1}.0.0"
      end
    end

    def current_gem_version(gem_root)
      version_file = File.join(gem_root, "lib", "cpflow", "version.rb")
      content = File.read(version_file)
      match = content.match(/VERSION = "([^"]+)"/)
      abort "Unable to read current gem version from #{version_file}" unless match

      match[1]
    end

    def extract_latest_changelog_version(gem_root:)
      changelog_path = File.join(gem_root, "CHANGELOG.md")
      return nil unless File.exist?(changelog_path)

      File.readlines(changelog_path).each do |line|
        match = line.match(/^## \[([^\]]+)\]/)
        next unless match

        version = match[1].strip
        next if version == "Unreleased"

        return version if version.match?(VERSION_PATTERN)
      end

      nil
    end

    def extract_changelog_section(gem_root:, version:)
      changelog_path = File.join(gem_root, "CHANGELOG.md")
      lines = File.readlines(changelog_path)
      section_header = /^## \[#{Regexp.escape(version)}\]/
      start_index = lines.index { |line| line.match?(section_header) }
      return nil unless start_index

      end_index = ((start_index + 1)...lines.length).find { |idx| lines[idx].start_with?("## [") } || lines.length
      content = lines[(start_index + 1)...end_index].join.strip
      return nil if content.empty?

      content
    end

    def resolve_version_input(version_input, gem_root:)
      stripped = version_input.to_s.strip
      return stripped unless stripped.empty?

      changelog_version = extract_latest_changelog_version(gem_root: gem_root)
      current_version = current_gem_version(gem_root)

      if changelog_version && Gem::Version.new(changelog_version) > Gem::Version.new(current_version)
        puts "Found CHANGELOG.md version: #{changelog_version} (current: #{current_version})"
        return changelog_version
      end

      if changelog_version &&
         Gem::Version.new(changelog_version) == Gem::Version.new(current_version) &&
         !version_tagged?(gem_root, changelog_version)
        puts "Found untagged CHANGELOG.md version: #{changelog_version} (current: #{current_version})"
        return changelog_version
      end

      if changelog_version && prerelease_version?(changelog_version)
        changelog_components = parse_gem_version_components(changelog_version)
        current_components = parse_gem_version_components(current_version)
        same_release_base = changelog_components[:major] == current_components[:major] &&
                            changelog_components[:minor] == current_components[:minor] &&
                            changelog_components[:patch] == current_components[:patch]

        if same_release_base && !version_tagged?(gem_root, changelog_version)
          puts "Found untagged CHANGELOG.md prerelease version: #{changelog_version} (current: #{current_version})"
          return changelog_version
        end
      end

      puts "No new version found in CHANGELOG.md (latest: #{changelog_version || 'none'}, current: #{current_version})."
      puts "Falling back to patch bump."
      "patch"
    end

    def parse_release_tag_to_gem_version(tag)
      stable_match = tag.match(/\Av(\d+\.\d+\.\d+)\z/)
      return stable_match[1] if stable_match

      prerelease_with_dot = tag.match(/\Av(\d+\.\d+\.\d+)\.(test|beta|alpha|rc|pre)\.(\d+)\z/i)
      if prerelease_with_dot
        return "#{prerelease_with_dot[1]}.#{prerelease_with_dot[2].downcase}.#{prerelease_with_dot[3]}"
      end

      prerelease_with_dash = tag.match(/\Av(\d+\.\d+\.\d+)-(test|beta|alpha|rc|pre)\.(\d+)\z/i)
      return unless prerelease_with_dash

      "#{prerelease_with_dash[1]}.#{prerelease_with_dash[2].downcase}.#{prerelease_with_dash[3]}"
    end

    def tagged_release_gem_versions(gem_root, fetch_tags: true)
      if fetch_tags
        fetch_output, fetch_status = Open3.capture2e("git", "-C", gem_root, "fetch", "--tags", "--quiet")
        abort "Unable to fetch tags for version validation.\n\n#{fetch_output.strip}" unless fetch_status.success?
      end

      tags_output, tags_status = Open3.capture2e("git", "-C", gem_root, "tag", "-l", "v*")
      abort "Unable to list git tags for version validation.\n\n#{tags_output.strip}" unless tags_status.success?

      tags_output.lines.map(&:strip).filter_map { |tag| parse_release_tag_to_gem_version(tag) }.uniq
    end

    def version_tagged?(gem_root, version)
      tagged_release_gem_versions(gem_root, fetch_tags: true).include?(version)
    end

    def version_bump_type(previous_stable_gem_version:, target_gem_version:)
      previous = parse_gem_version_components(previous_stable_gem_version)
      target = parse_gem_version_components(target_gem_version)

      return :major if target[:major] > previous[:major]
      return :minor if target[:major] == previous[:major] && target[:minor] > previous[:minor]
      return :patch if target[:major] == previous[:major] &&
                       target[:minor] == previous[:minor] &&
                       target[:patch] > previous[:patch]

      :none
    end

    def expected_bump_type_from_changelog_section(changelog_section)
      section = changelog_section.to_s
      return :major if section.match?(/^####?\s+(?:Breaking(?:\s+Changes?)?)\b/i)
      return :minor if section.match?(/^####?\s+(Added|New\s+Features?|Features?|Enhancements?)\b/i)

      patch_headings = /^####?\s+(Fixed|Fixes|Bug\s+Fixes?|Security|Improved|Changed|Deprecated|Removed)\b/i
      return :patch if section.match?(patch_headings)

      nil
    end

    def handle_version_policy_violation!(message:, allow_override:)
      if allow_override
        puts "VERSION POLICY OVERRIDE: #{message}"
        return
      end

      abort message
    end

    def validate_release_version_policy!(gem_root:, target_gem_version:, allow_override:, fetch_tags: true)
      tagged_versions = tagged_release_gem_versions(gem_root, fetch_tags: fetch_tags)
      latest_tagged_version = tagged_versions.max_by { |version| Gem::Version.new(version) }

      if latest_tagged_version && Gem::Version.new(target_gem_version) <= Gem::Version.new(latest_tagged_version)
        handle_version_policy_violation!(
          message: "Requested version #{target_gem_version} must be greater than latest tag #{latest_tagged_version}.",
          allow_override: allow_override
        )
      end

      if prerelease_version?(target_gem_version) && latest_tagged_version
        target_components = parse_gem_version_components(target_gem_version)
        latest_components = parse_gem_version_components(latest_tagged_version)
        same_release_base = target_components[:major] == latest_components[:major] &&
                            target_components[:minor] == latest_components[:minor] &&
                            target_components[:patch] == latest_components[:patch]

        return if same_release_base && prerelease_version?(latest_tagged_version)
      end

      latest_stable_version = tagged_versions.reject { |version| prerelease_version?(version) }
                                             .max_by { |version| Gem::Version.new(version) }
      return unless latest_stable_version

      actual_bump_type = version_bump_type(
        previous_stable_gem_version: latest_stable_version,
        target_gem_version: target_gem_version
      )

      if actual_bump_type == :none
        handle_version_policy_violation!(
          message: "Requested version #{target_gem_version} is not a bump over latest stable #{latest_stable_version}.",
          allow_override: allow_override
        )
        return if allow_override
      end

      return if prerelease_version?(target_gem_version)

      changelog_section = extract_changelog_section(gem_root: gem_root, version: target_gem_version)
      return unless changelog_section

      expected_bump_type = expected_bump_type_from_changelog_section(changelog_section)
      return unless expected_bump_type
      return if actual_bump_type == expected_bump_type

      handle_version_policy_violation!(
        message: "Version bump mismatch for #{target_gem_version}: CHANGELOG implies #{expected_bump_type}, " \
                 "but the version bump is #{actual_bump_type} from #{latest_stable_version}.",
        allow_override: allow_override
      )
    end

    def confirm_release!(version:, gem_root:)
      has_changelog = extract_changelog_section(gem_root: gem_root, version: version)

      puts ""
      puts "Release confirmation"
      puts "  Version: #{version}"
      puts "  Changelog: #{has_changelog ? 'section found' : 'missing; GitHub release sync will be skipped'}"
      print "Proceed with release? [y/N] "
      $stdout.flush
      answer = $stdin.gets&.strip&.downcase
      abort "Release aborted." unless answer == "y"
    end

    def current_git_branch(gem_root)
      output, status = Open3.capture2e("git", "-C", gem_root, "rev-parse", "--abbrev-ref", "HEAD")
      abort "Failed to determine current git branch.\n\n#{output}" unless status.success?

      output.strip
    end

    def ensure_release_branch_allowed!(current_branch:, target_gem_version:)
      return if prerelease_version?(target_gem_version)
      return if current_branch == "main"

      abort <<~ERROR
        Release must be run from the main branch.

        Current branch: #{current_branch}

        For stable releases:
          git checkout main
          git pull --rebase
          bundle exec rake release

        Pre-release versions such as #{target_gem_version}.rc.0 may be released from non-main branches.
      ERROR
    end

    def ensure_there_is_nothing_to_commit(gem_root = self.gem_root)
      status = `git -C #{Shellwords.escape(gem_root)} status --porcelain`
      return if $CHILD_STATUS.success? && status == ""

      error = if $CHILD_STATUS.success?
                "You have uncommitted code. Please commit or stash your changes before releasing."
              else
                "Git is required before releasing."
              end
      raise(error)
    end

    def verify_gem_release_available!
      output, status = Open3.capture2e("bundle", "exec", "gem", "bump", "--help")
      abort "gem-release is required. Run `bundle install`.\n\n#{output}" unless status.success?
    end

    def github_repo_slug(gem_root)
      origin_url, status = Open3.capture2e("git", "-C", gem_root, "remote", "get-url", "origin")
      abort "Unable to determine git origin URL.\n\n#{origin_url}" unless status.success?

      match = origin_url.strip.match(%r{github\.com[:/](?<repo>[^/]+/[^/]+?)(?:\.git)?\z})
      abort "Unable to determine GitHub repository from origin URL #{origin_url.inspect}" unless match

      match[:repo]
    end

    def capture_gh_output(*args)
      Open3.capture2e("gh", *args)
    rescue Errno::ENOENT
      abort "GitHub CLI (`gh`) is not installed. Install it from https://cli.github.com/ and retry."
    end

    def verify_gh_auth(gem_root:)
      result, status = capture_gh_output("auth", "status")
      abort "GitHub CLI authentication required. Run `gh auth login`.\n\n#{result}" unless status.success?

      repo_slug = github_repo_slug(gem_root)
      permission_result, permission_status = capture_gh_output("api", "repos/#{repo_slug}", "--jq", ".permissions.push")

      unless permission_status.success?
        abort "GitHub CLI authenticated, but write access check failed for #{repo_slug}.\n\n#{permission_result}"
      end

      unless permission_result.strip == "true"
        abort "GitHub CLI account/token does not have write access to #{repo_slug}."
      end

      puts "GitHub CLI authenticated with write access to #{repo_slug}."
    end

    def run_release_preflight_checks!(gem_root:, dry_run:)
      verify_gem_release_available!
      return if dry_run

      verify_gh_auth(gem_root: gem_root)
    end

    def sh_in_dir(dir, *shell_commands)
      Dir.chdir(dir) do
        shell_commands.flatten.each { |shell_command| sh(shell_command.strip) }
      end
    end

    def sh_args_in_dir(dir, *command_args, env: nil)
      Dir.chdir(dir) do
        env ? sh(env, *command_args) : sh(*command_args)
      end
    end

    def unbundled_sh_in_dir(dir, *shell_commands)
      Dir.chdir(dir) do
        Bundler.with_unbundled_env do
          shell_commands.flatten.each { |shell_command| sh(shell_command.strip) }
        end
      end
    end

    def update_the_local_project(gem_root = self.gem_root)
      puts "Pulling latest commits from remote repository."
      sh_args_in_dir(gem_root, "git", "pull", "--rebase")
    rescue Errno::ENOENT
      raise "Ensure you have Git and Bundler installed before releasing."
    end

    def with_release_checkout(gem_root:, dry_run:)
      return yield(gem_root) unless dry_run

      Dir.mktmpdir("cpflow-release-dry-run") do |tmpdir|
        worktree_dir = File.join(tmpdir, "worktree")
        sh_args_in_dir(gem_root, "git", "worktree", "add", "--detach", worktree_dir, "HEAD")
        begin
          yield(worktree_dir)
        ensure
          sh_args_in_dir(gem_root, "git", "worktree", "remove", "--force", worktree_dir)
        end
      end
    end

    def bump_gem_version!(gem_root:, version_input:)
      action = semver_keyword?(version_input) ? "Bumping #{version_input}" : "Setting"
      puts "#{action} cpflow gem version..."
      sh_args_in_dir(gem_root, "bundle", "exec", "gem", "bump", "--no-commit", "--version", version_input)
    end

    def update_lockfile!(gem_root:)
      quiet_flag = ENV["VERBOSE"] == "1" ? "" : " --quiet"
      unbundled_sh_in_dir(gem_root, "bundle install#{quiet_flag}")
    end

    def commit_tag_and_push!(gem_root:, version:)
      sh_args_in_dir(gem_root, "git", "add", "-A", "Gemfile.lock", "lib/cpflow/version.rb")

      _git_diff_output, git_diff_status = Open3.capture2e("git", "-C", gem_root, "diff", "--cached", "--quiet")
      if git_diff_status.success?
        puts "No version changes to commit; version is already #{version}."
      else
        sh_args_in_dir(gem_root, "git", "commit", "-m", "Bump version to #{version}")
      end

      tag_name = "v#{version}"
      tag_exists = system("git", "-C", gem_root, "rev-parse", "--verify", "--quiet", "refs/tags/#{tag_name}",
                          out: File::NULL, err: File::NULL)
      abort "Unable to verify git tag #{tag_name}." if tag_exists.nil?

      if tag_exists
        puts "Git tag #{tag_name} already exists; skipping tag creation."
      else
        sh_args_in_dir(gem_root, "git", "tag", tag_name)
      end

      sh_args_in_dir(gem_root, "git", "push")
      sh_args_in_dir(gem_root, "git", "push", "--tags")
    end

    def normalize_otp_code(otp)
      return nil if otp.nil?

      normalized = otp.to_s.strip
      abort "Invalid RubyGems OTP. Expected digits only." unless normalized.match?(/\A\d+\z/)

      normalized
    end

    def prompt_for_otp
      print "Enter RubyGems OTP code: "
      $stdout.flush
      otp = $stdin.gets&.strip
      abort "No RubyGems OTP provided. Aborting." if otp.nil? || otp.empty?

      normalize_otp_code(otp)
    end

    def publish_gem_with_retry(dir, gem_name, otp: nil, max_retries: ENV.fetch("GEM_RELEASE_MAX_RETRIES", "3").to_i)
      puts ""
      puts "Publishing #{gem_name} gem to RubyGems.org..."
      current_otp = normalize_otp_code(otp)
      current_otp ||= prompt_for_otp

      retry_count = 0
      loop do
        gem_release_env = { "GEM_HOST_OTP_CODE" => current_otp }
        sh_args_in_dir(dir, "bundle", "exec", "gem", "release", env: gem_release_env)
        return current_otp
      rescue RuntimeError, IOError => e
        retry_count += 1
        raise e if retry_count >= max_retries

        puts "RubyGems release failed (attempt #{retry_count}/#{max_retries})."
        puts "Error: #{e.class}: #{e.message}"
        puts "Enter a fresh OTP to retry."
        current_otp = prompt_for_otp
      end
    end

    def changelog_dirty?(gem_root:)
      changes_output, status = Open3.capture2e("git", "-C", gem_root, "status", "--porcelain", "--", "CHANGELOG.md")
      abort "Unable to check CHANGELOG.md status.\n\n#{changes_output.strip}" unless status.success?

      !changes_output.strip.empty?
    end

    def ensure_changelog_committed!(gem_root:)
      return unless changelog_dirty?(gem_root: gem_root)

      abort "CHANGELOG.md has uncommitted changes. Commit or stash it before syncing GitHub releases."
    end

    def ensure_git_tag_exists!(gem_root:, tag:)
      fetch_output, fetch_status = Open3.capture2e("git", "-C", gem_root, "fetch", "--tags", "--quiet")
      unless fetch_status.success?
        abort "Unable to fetch git tags before verifying #{tag.inspect}.\n\n#{fetch_output.strip}"
      end

      tag_ref = "refs/tags/#{tag}"
      tag_exists = system("git", "-C", gem_root, "rev-parse", "--verify", "--quiet", tag_ref,
                          out: File::NULL, err: File::NULL)
      abort "Unable to run git to verify tag #{tag.inspect}." if tag_exists.nil?
      return if tag_exists

      abort "Git tag #{tag.inspect} was not found locally or remotely."
    end

    def prepare_github_release_context(gem_root:, gem_version:)
      notes = extract_changelog_section(gem_root: gem_root, version: gem_version)
      abort "Could not find `## [#{gem_version}]` in CHANGELOG.md. Add that section and retry." unless notes

      {
        notes: notes,
        prerelease: prerelease_version?(gem_version),
        tag: "v#{gem_version}",
        title: "v#{gem_version}"
      }
    end

    def publish_or_update_github_release(gem_root:, release_context:, dry_run:)
      ensure_git_tag_exists!(gem_root: gem_root, tag: release_context[:tag])

      if dry_run
        puts "DRY RUN: Would create or update GitHub release #{release_context[:tag]}."
        return
      end

      Tempfile.create(["cpflow-release-notes-", ".md"]) do |tmp|
        tmp.write(release_context[:notes])
        tmp.flush

        release_exists = system("gh", "release", "view", release_context[:tag],
                                chdir: gem_root,
                                out: File::NULL,
                                err: File::NULL)
        abort "Unable to run `gh`." if release_exists.nil?

        release_command = github_release_command(release_context: release_context, notes_file: tmp.path,
                                                 release_exists: release_exists)
        sh_args_in_dir(gem_root, *release_command)
      end
    end

    def github_release_command(release_context:, notes_file:, release_exists:)
      if release_exists
        return ["gh", "release", "edit", release_context[:tag], "--title", release_context[:title],
                "--notes-file", notes_file, "--prerelease=#{release_context[:prerelease]}"]
      end

      command = ["gh", "release", "create", release_context[:tag], "--verify-tag", "--title",
                 release_context[:title], "--notes-file", notes_file]
      command << "--prerelease" if release_context[:prerelease]
      command
    end

    def sync_github_release_after_publish(gem_root:, gem_version:, dry_run:)
      section = extract_changelog_section(gem_root: gem_root, version: gem_version)
      unless section
        puts ""
        puts "Skipping GitHub release: no CHANGELOG.md section for #{gem_version}."
        puts "After adding and committing the changelog section, run:"
        puts "bundle exec rake \"sync_github_release[#{gem_version}]\""
        return
      end

      verify_gh_auth(gem_root: gem_root)
      release_context = prepare_github_release_context(gem_root: gem_root, gem_version: gem_version)
      publish_or_update_github_release(gem_root: gem_root, release_context: release_context, dry_run: dry_run)
    end
  end
end
# rubocop:enable Metrics/BlockLength, Metrics/ClassLength, Metrics/CyclomaticComplexity
# rubocop:enable Metrics/MethodLength, Metrics/ModuleLength, Metrics/PerceivedComplexity
