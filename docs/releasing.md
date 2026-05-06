# Releasing the Gem

This project follows a changelog-first Ruby gem release process, modeled after
the React on Rails release flow but without any npm publishing steps.

## Release Process

### 1. Update the Changelog

Always update `CHANGELOG.md` before running the release task.

1. Ensure all desired changes are merged to `main`.
2. Move the relevant `Unreleased` entries into a versioned header:

   ```markdown
   ## [4.2.0] - 2026-05-05
   ```

3. Verify the version number matches the intended release level:
   - Breaking changes: major
   - Added features or enhancements: minor
   - Fixes, improvements, deprecations, removals, or security updates: patch
4. Update the compare links at the bottom of `CHANGELOG.md`, including the
   `Unreleased` link and the new version link.
5. Commit, push, review, and merge the changelog update before releasing.

The release task reads the latest versioned `CHANGELOG.md` header and can create
the GitHub release from that section automatically.

### 2. Run the Release Task

The recommended command has no arguments:

```bash
bundle exec rake release
```

With no arguments, `rake release`:

1. Reads the first versioned `CHANGELOG.md` header, such as `## [4.2.0]`.
2. Uses that version when it is newer than the current gem version.
3. Uses the current version if the changelog version matches the gem version
   but has not been tagged yet.
4. Falls back to a patch bump if no new changelog version is found.

Other supported forms:

```bash
bundle exec rake "release[patch]"
bundle exec rake "release[minor]"
bundle exec rake "release[major]"
bundle exec rake "release[4.2.0]"
bundle exec rake "release[4.2.0.rc.1]"
bundle exec rake "release[4.2.0,true]"
```

Use RubyGems version format for prereleases: `4.2.0.rc.1`, not
`4.2.0-rc.1`.

Full argument list:

```bash
bundle exec rake "release[version,dry_run,override_version_policy]"
```

Environment variables:

```bash
VERBOSE=1
RUBYGEMS_OTP=<code>
RELEASE_VERSION_POLICY_OVERRIDE=true
GEM_RELEASE_MAX_RETRIES=<n>
```

### 3. What the Task Does

`bundle exec rake release` performs the gem-only release:

1. Requires a clean working tree.
2. Verifies `gem-release` is available through Bundler.
3. For real releases, verifies GitHub CLI authentication and write access.
4. Pulls the latest changes with `git pull --rebase`.
5. Resolves the target version from the changelog or explicit argument.
6. Requires stable releases to run from `main`; prereleases may run from another
   branch.
7. Validates the target version is newer than the latest tag and is consistent
   with the changelog section when the section indicates a bump level.
8. Bumps `lib/cpflow/version.rb` and updates `Gemfile.lock`.
9. Commits the version bump, tags `vX.Y.Z`, and pushes the commit and tags.
10. Publishes the `cpflow` gem to RubyGems.org.
11. Creates or updates the GitHub release from the matching changelog section.

The older `bundle exec rake "create_release[4.2.0,false]"` task name remains as
a compatibility alias, but new releases should use `bundle exec rake release`.

### 4. Sync GitHub Release Notes Manually

If the GitHub release was not created automatically, update and commit the
matching changelog section, then run:

```bash
bundle exec rake "sync_github_release[4.2.0]"
bundle exec rake "sync_github_release[4.2.0,true]"
```

`sync_github_release` reads notes from `CHANGELOG.md` and creates or updates the
GitHub release for the corresponding `vX.Y.Z` tag.

## Pre-Release Checklist

Before running the release:

1. `git checkout main`
2. `git pull --rebase`
3. `bundle install`
4. `gh auth status`
5. Confirm RubyGems credentials can publish `cpflow`.
6. Confirm `CHANGELOG.md` has a committed section for the target version.
7. Run a dry run:

   ```bash
   bundle exec rake "release[4.2.0,true]"
   ```

## If a Release Fails

Check what was published before retrying:

```bash
gem list cpflow -r -a
gh release view v4.2.0
git tag -l v4.2.0
```

If the gem was published but GitHub release creation failed, fix GitHub CLI
authentication or permissions and run:

```bash
bundle exec rake "sync_github_release[4.2.0]"
```

If the tag was pushed but the gem was not published, delete or correct the tag
and version commit intentionally before trying again.
