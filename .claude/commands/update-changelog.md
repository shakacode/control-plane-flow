# Update Changelog

You are helping to add an entry to the CHANGELOG.md file for the cpflow gem (the `shakacode/control-plane-flow` repository).

## Arguments

This command accepts an optional argument: `$ARGUMENTS`

- **No argument** (`/update-changelog`): Add entries to `[Unreleased]` without stamping a version header. Use this during development.
- **`release`** (`/update-changelog release`): Add entries and stamp a version header. Auto-compute the next version based on changes (breaking -> major, added features -> minor, fixes -> patch). Then `bundle exec rake release` (with no args) will pick up this version automatically.
- **`rc`** (`/update-changelog rc`): Same as `release`, but stamps an RC prerelease version (e.g., `5.0.0.rc.0`). Auto-increments the RC index if prior RCs exist for the same base version.
- **`beta`** (`/update-changelog beta`): Same as `rc`, but stamps a beta prerelease version (e.g., `5.0.0.beta.0`).
- **Explicit version** (`/update-changelog 5.0.0.rc.10`): Add entries and stamp the exact version provided. Skips auto-computation — use this when you already know the target version. The version string must look like a RubyGems-style version (with optional `.rc.N`, `.beta.N`, `.alpha.N`, `.pre.N`, or `.test.N` suffix).

## When to Use This

This command serves three use cases at different points in the release lifecycle:

**During development** -- Add entries to `[Unreleased]` as PRs merge:

- Run `/update-changelog` to find merged PRs missing from the changelog
- Entries accumulate under `## [Unreleased]`

**Before a release** -- Stamp a version header and prepare for release:

- Run `/update-changelog release` (or `rc`, `beta`, or an explicit version like `5.0.0.rc.10`) to add entries AND stamp the version header
- The version is auto-computed from changes (breaking -> major, features -> minor, fixes -> patch) — skipped when an explicit version is provided
- The command automatically commits, pushes, and opens a PR — review and merge it
- Then run `bundle exec rake release` (no args needed -- it reads the version from CHANGELOG.md)
- The release task automatically creates a GitHub release from the changelog section

**After a release you forgot to update the changelog for** -- Catch-up mode:

- The command can retroactively find commits between tags and add missing entries
- Ask the user whether to stamp a version header or add to `[Unreleased]`

### Why changelog comes BEFORE the release

- `bundle exec rake release` automatically creates a GitHub release if a changelog section exists -- no separate `sync_github_release` step needed
- The release task warns if no changelog section is found for the target version
- A premature version header (if release fails) is harmless -- you'll release eventually
- A missing changelog after release means the GitHub release must be created manually via `bundle exec rake "sync_github_release[X.Y.Z]"`

## Auto-Computing the Next Version

When stamping a version header (`release`, `rc`, or `beta`), compute the next version as follows:

1. **Find the latest stable version tag** using semver sort:

   ```bash
   git tag -l 'v*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1
   ```

2. **Determine bump type from changelog content**:
   - If changes include `### Breaking Changes` (or `#### Breaking Changes`) -> **major** bump
   - If changes include `### Added`, `### New Features`, `### Features`, or `### Enhancements` -> **minor** bump
   - If changes only include `### Fixed`, `### Security`, `### Improved`, `### Changed`, `### Deprecated`, or `### Removed` -> **patch** bump

   Note: the `rake release` task validates the bump level against these headings via `expected_bump_type_from_changelog_section` in `rakelib/create_release.rake`. If the bump does not match, the release is aborted unless `RELEASE_VERSION_POLICY_OVERRIDE=true` is set.

3. **Compute the version**:
   - For `release`: Apply the bump to the latest stable tag (e.g., `4.2.0` + minor -> `4.3.0`; `4.2.0` + major -> `5.0.0`)
   - For `rc`: Apply the bump, then find the next RC index based **only on git tags** (e.g., if `v5.0.0.rc.0` tag exists -> `5.0.0.rc.1`). **Do NOT use changelog headers** to determine the next index — a version header in the changelog is a draft that may not have been released yet. Only git tags represent shipped versions.
   - For `beta`: Same as RC but with beta suffix

4. **Verify**: Check that the computed version is newer than ALL existing tags (stable and prerelease). If not, ask the user what to do.

5. **Show the computed version to the user and ask for confirmation** before stamping the header. If the bump type is ambiguous (e.g., changes could reasonably be classified as patch vs minor, or the changelog headings don't clearly signal the bump level), explain your reasoning for the suggested bump and ask the user to confirm or override before proceeding.

## Critical Requirements

1. **User-visible changes only**: Only add changelog entries for user-visible changes:
   - New features and CLI commands
   - Bug fixes
   - Breaking changes (CLI behavior, exit codes, generator output, configuration schema)
   - Deprecations
   - Performance improvements
   - Security fixes
   - Changes to public APIs, command flags, or configuration options

2. **Do NOT add entries for**:
   - Linting fixes
   - Code formatting / RuboCop changes
   - Internal refactoring
   - Test updates
   - Documentation fixes (unless they fix incorrect docs about behavior)
   - CI/CD-only changes (workflow tweaks that don't affect users)

## Formatting Requirements

### Entry Format

Each changelog entry MUST follow this exact format:

```markdown
- **Bold description of change**. [PR 278](https://github.com/shakacode/control-plane-flow/pull/278) by [Justin Gordon](https://github.com/justin808). Optional additional context or details.
```

**Important formatting rules**:

- Start with a dash and space: `- `
- Use **bold** for the main description (or for breaking-change scope labels — see below)
- End the bold description with a period before the link
- Always link to the PR: `[PR 278](https://github.com/shakacode/control-plane-flow/pull/278)` - **NO hash symbol**
- Always link to the author by their display name: `by [Justin Gordon](https://github.com/justin808)`. Match the existing style in `CHANGELOG.md` — full name preferred when known, GitHub handle as a fallback.
- End with a period after the author link
- Additional details can be added after the main entry, using proper indentation for multi-line entries

### Breaking Changes Format

Breaking changes in this repo typically open with the literal phrase `BREAKING CHANGE:` to maximize visibility (see existing entries in `## [Unreleased]`). Example:

```markdown
- BREAKING CHANGE: `cpflow exists` now returns exit code 3 when the app is not found, preserving 64 for real errors so scripts can distinguish not-found from API/auth failures. Affected callers: only scripts that branched specifically on `[ $? -eq 64 ]` as a "not found" signal — those will now misroute "not found" into the error branch and must switch to checking for exit 3. Scripts that treat any non-zero exit as "not found" are unaffected. The change is isolated to `lib/command/exists.rb` and `lib/constants/exit_code.rb` (`NOT_FOUND = 3`), so users hitting a regression can bisect by file. [PR 278](https://github.com/shakacode/control-plane-flow/pull/278) by [Justin Gordon](https://github.com/justin808).
```

For breaking changes that warrant a step-by-step migration guide, append it inline:

```markdown
- BREAKING CHANGE: Description of the breaking change. See migration guide below. [PR 278](https://github.com/shakacode/control-plane-flow/pull/278) by [Justin Gordon](https://github.com/justin808).

  **Migration Guide:**

  1. Step one
  2. Step two
```

### Category Organization

Entries should be organized under these section headings **in the following order** (most critical first):

**Preferred section order:**

1. `### Breaking Changes` - Breaking changes (FIRST - most critical for upgrading users)
2. `### Added` - New features
3. `### Changed` - Changes to existing functionality
4. `### Improved` - Improvements to existing features
5. `### Fixed` - Bug fixes
6. `### Deprecated` - Deprecation notices
7. `### Removed` - Removed features
8. `### Security` - Security-related changes

**Rationale:** Breaking changes come first because they are the most critical information for anyone upgrading. Users need to know immediately if their code will break before seeing what new features are available.

**Note**: This project uses `###` (three hashes) for category headings because version headers use `##` (two hashes). Do not use `####` for category headings — that pattern belongs to projects whose version headers are `###`.

**Only include section headings that have entries.**

### Version Stamping

This repo does **not** have an `update_changelog` rake task — the slash command itself performs the stamping. After adding entries, do the following manually:

1. **Insert the version header** immediately after `## [Unreleased]` (and any short prose under it that belongs to Unreleased), in the form:

   ```markdown
   ## [4.3.0] - 2026-05-05
   ```

   Use today's date in `YYYY-MM-DD` form.

2. **Update the compare links** at the bottom of the file:
   - The `[unreleased]` link must compare from the new version tag to `HEAD`:

     ```markdown
     [Unreleased]: https://github.com/shakacode/control-plane-flow/compare/v4.3.0...HEAD
     ```

     Note: this repo uses `...HEAD`, not `...main`. Match the existing convention.
   - Add a new compare link for the stamped version:

     ```markdown
     [4.3.0]: https://github.com/shakacode/control-plane-flow/compare/v4.2.0...v4.3.0
     ```

     - **For stable releases**, skip prerelease tags — compare from the previous **stable** tag. A stable release that coalesces prior RCs (e.g., `v5.0.0.rc.0`, `v5.0.0.rc.1`) still uses the last stable tag as the left side (e.g., `v4.2.0...v5.0.0`), not the latest RC tag.
     - **For prereleases**, compare from the immediately previous tag (which may be a prior RC/beta or the last stable tag).

3. **For `rc`/`beta` modes**: Insert the new RC/beta section above any prior prereleases — do NOT collapse them. Each RC/beta is a separately-tagged release that users install, and they need to see what changed between, say, `rc.0` and `rc.1`. See "For Prerelease Versions" below. Coalescing happens only at the stable release.

The `rake release` task reads the first `## [VERSION]` header (skipping `Unreleased`) and uses it as the target version when newer than the current gem version. So once the changelog PR merges, `bundle exec rake release` (no args) will pick up the version automatically.

### Finding the Most Recent Version

To determine the most recent version:

1. **Check git tags** to find the latest released version:

   ```bash
   git tag --sort=-v:refname | head -10
   ```

   This shows tags like `v4.2.0`, `v4.1.1`, etc.

2. **Check the CHANGELOG.md** for version headers (note: changelog uses versions WITHOUT the `v` prefix):
   - `## [4.2.0] - 2026-04-15` (stable version)
   - `## [4.2.0.rc.0] - 2026-04-10` (prerelease, if/when used)

3. **Use this regex pattern** to find version headers in the changelog:

   ```regex
   ^## \[([^\]]+)\]( - \d{4}-\d{2}-\d{2})?
   ```

4. **The first match after `## [Unreleased]`** is the most recent version in the changelog.

**IMPORTANT**: Git tags use `v` prefix (e.g., `v4.2.0`). Changelog **headers** use versions WITHOUT the `v` prefix (e.g., `## [4.2.0]`), but compare **links** at the bottom of the file MUST use the `v` prefix to match the git tag (e.g., `.../compare/v4.1.1...v4.2.0`). Strip the `v` only for changelog headers, not for compare link URLs.

## Process

### For Regular Changelog Updates

#### Step 1: Fetch and read current state

- **CRITICAL**: Run `git fetch origin main` to ensure you have the latest commits
- After fetching, use `origin/main` for all comparisons, NOT local `main` branch
- Read the current CHANGELOG.md to understand the existing structure

#### Step 2: Reconcile tags with changelog sections (DO THIS FIRST)

**This step catches missing version sections and is the #1 source of errors when skipped.**

1. Get the latest git tag: `git tag --sort=-v:refname | head -5`
2. Get the most recent version header in CHANGELOG.md (the first `## [VERSION] - DATE` after `## [Unreleased]`)
3. **Compare them.** If the latest git tag (minus the `v` prefix) does NOT appear anywhere in the changelog version headers, there are tagged releases missing from the changelog. **Important**: Don't just compare against the _top_ changelog header — a version header may exist _above_ the latest tag if it was stamped as a draft before tagging. Check whether the tag's version appears in _any_ `## [X.Y.Z]` header. For example:
   - Latest tag: `v4.2.0`, and no `## [4.2.0]` header exists anywhere in CHANGELOG.md
   - **Result: `4.2.0` is missing and needs its own section**
   - But if `## [5.0.0]` is the top header (a draft, not yet tagged) and `## [4.2.0]` exists below it, then nothing is missing — the top header is simply a pre-release draft

4. For EACH missing tagged version (there may be multiple):
   a. Find commits in that tag vs the previous tag: `git log --oneline PREV_TAG..MISSING_TAG`
   b. Extract PR numbers and fetch details for user-visible changes
   c. Check which entries currently in `## [Unreleased]` actually belong to this tagged version (compare PR numbers against the commit list)
   d. **Create a new version section** immediately before the previous version section:

   ```markdown
   ## [4.2.0] - 2026-04-15
   ```

   e. **Move** matching entries from Unreleased into the new section
   f. **Add** any new entries for PRs in that tag that aren't in the changelog at all
   g. **Update version diff links** at the bottom of the file:
   - Update `[unreleased]` to compare from the newest tag to `HEAD`
   - Add a link for each new version section

5. Get the tag date with: `git log -1 --format="%Y-%m-%d" TAG_NAME`

#### Step 3: Add new entries for post-tag commits

1. Run `git log --oneline LATEST_TAG..origin/main` to find commits after the latest tag (LATEST_TAG is the most recent git tag, i.e., the same one identified in Step 2)
2. Extract PR numbers: `git log --oneline LATEST_TAG..origin/main | grep -oE "#[0-9]+" | sort -u`
3. If Step 2 found no missing tagged versions, verify no tag is ahead of main: `git log --oneline origin/main..LATEST_TAG` should be empty. If not, entries in "Unreleased" may belong to that tagged version — Step 2 should have caught this, so re-check.
4. For each PR number, check if it's already in CHANGELOG.md: `grep "PR XXX" CHANGELOG.md`
5. For PRs not yet in the changelog:
   - Get PR details: `gh pr view NUMBER --json title,body,author --repo shakacode/control-plane-flow`
   - **Never ask the user for PR details** - get them from git history or the GitHub API
   - Validate that the change is user-visible (per the criteria above). Skip CI, lint, refactoring, test-only changes.
   - Add the entry to `## [Unreleased]` under the appropriate category heading

#### Step 4: Stamp version header (only when a version mode or explicit version is given)

If the user passed `release`, `rc`, `beta`, or an explicit version string as an argument:

1. Determine the target version (auto-computed for `release`/`rc`/`beta`, exact for an explicit version) using the rules in "Auto-Computing the Next Version" above.

2. Confirm the version with the user.

3. **Stamp the header** by inserting `## [TARGET_VERSION] - YYYY-MM-DD` immediately after the `## [Unreleased]` block (after any short prose lines under Unreleased that should remain there).

4. **Update compare links** at the bottom of the file:
   - Update `[Unreleased]` to compare from the new tag to `HEAD`
   - Add a new compare link for the stamped version

5. **For `rc`/`beta`**: Do NOT collapse prior prerelease sections — each RC/beta gets its own section so users can see what changed between prereleases. Just insert the new section above the prior ones and add a new compare link. See "For Prerelease Versions" below.

6. **For stable `release` (or explicit stable version) when prior `rc`/`beta` sections exist for the same base version**: Do NOT just stamp `## [5.0.0]` above the prior RC sections. Instead, follow the "For Prerelease to Stable Version Release" process below — it replaces steps 3–4 here with the coalesce + curate flow (combine all RC sections into the new stable section, move any matching `[Unreleased]` entries in, drop prerelease-only noise, and use the previous **stable** tag in the compare link).

7. **Verify** the stamped header and diff links match the requested version. If anything looks off, fix it before continuing.

If no argument was passed, skip this step -- entries stay in `## [Unreleased]`.

#### Step 5: Verify and finalize

1. **Verify formatting**:
   - Bold description with period (or `BREAKING CHANGE:` prefix for breaking changes)
   - Proper PR link (NO hash symbol)
   - Proper author link
   - Consistent with existing entries
   - File ends with a newline character
   - **No duplicate section headings** (e.g., don't create two `### Fixed` sections — merge entries into the existing heading)
2. **Verify version sections are in order** (Unreleased -> newest tag -> older tags)
3. **Verify version diff links** at the bottom of the file are correct (compare links MUST use the `v` prefix to match git tags; the `[Unreleased]` target is `HEAD`, not `main`)
4. **Show the user** a summary of what was done:
   - Which version sections were created
   - Which entries were moved from Unreleased
   - Which new entries were added
   - Which PRs were skipped (and why)
5. If in `release`/`rc`/`beta` mode or explicit-version mode, **automatically commit, push, and open a PR**:
   - Verify the working tree only has `CHANGELOG.md` changes; if there are other uncommitted changes, warn the user and stop
   - Verify the current branch is `main` (`git branch --show-current`); if not, warn the user and stop
   - Create a feature branch following the user's branch-naming convention (e.g., `jg/changelog-4.3.0` or `changelog-4.3.0`)
   - Stage only `CHANGELOG.md` (`git add CHANGELOG.md`) and commit with message `Update CHANGELOG.md for VERSION` (using the stamped version)
   - Push and open a PR with the changelog diff as the body
   - If the push or PR creation fails, the CHANGELOG is already stamped locally — fix the issue (e.g., authentication, branch protection), then run `git push -u origin <branch>` and `gh pr create` manually
   - Remind the user to run `bundle exec rake release` (no args) after the PR merges to publish and auto-create the GitHub release

### For Prerelease Versions (RC and Beta)

When the user passes `rc` or `beta` as an argument:

1. **Find the latest tag** (stable or prerelease) using semver sort:

   ```bash
   git tag -l 'v*' --sort=-v:refname | head -10
   ```

2. **Auto-compute the next prerelease version** using the process in "Auto-Computing the Next Version" above. Use RubyGems format (`5.0.0.rc.0`), not `5.0.0-rc.0`.

3. **Do NOT collapse prior prereleases.** Each RC/beta is a separately-tagged release that users install — they need to see what changed between, for example, `rc.0` and `rc.1` (especially when diagnosing a regression in a specific RC). Each successive `bundle exec rake release` reads only the top-most `## [VERSION]` section (the RC you just stamped — see the "Version Stamping" section above), so as long as each RC has its own section the corresponding GitHub release gets its own focused notes. Instead:

   - Insert the new prerelease version section immediately after `## [Unreleased]`, **above** any prior prerelease sections (preserves newest-first ordering)
   - Move any entries from `## [Unreleased]` that belong to this prerelease into the new section
   - Leave prior prerelease sections (e.g., `## [5.0.0.rc.0]`) untouched — keep their entries and their compare links at the bottom of the file
   - Add any new user-visible changes from commits since the last prerelease tag to the new section only
   - Add a new compare link at the bottom comparing the previous prerelease tag (or the last stable tag if this is the first RC) to the new prerelease tag
   - Update the `[Unreleased]` compare link to point from the new prerelease tag to `HEAD`

**Resulting structure** after stamping `5.0.0.rc.1` (with `5.0.0.rc.0` already shipped on top of stable `4.2.0`):

```markdown
## [Unreleased]

## [5.0.0.rc.1] - 2026-05-25

### Fixed

- **Fix regression introduced in rc.0**. [PR 320](https://github.com/shakacode/control-plane-flow/pull/320) by [Justin Gordon](https://github.com/justin808).

## [5.0.0.rc.0] - 2026-05-10

### Added

- **New feature**. [PR 315](https://github.com/shakacode/control-plane-flow/pull/315) by [Justin Gordon](https://github.com/justin808).

## [4.2.0] - 2026-04-01

...

[Unreleased]: https://github.com/shakacode/control-plane-flow/compare/v5.0.0.rc.1...HEAD
[5.0.0.rc.1]: https://github.com/shakacode/control-plane-flow/compare/v5.0.0.rc.0...v5.0.0.rc.1
[5.0.0.rc.0]: https://github.com/shakacode/control-plane-flow/compare/v4.2.0...v5.0.0.rc.0
[4.2.0]: https://github.com/shakacode/control-plane-flow/compare/v4.1.1...v4.2.0
```

Both RC sections remain intact with their own compare links until the stable release coalesces them.

**Coalescing happens only at the stable release** — see "For Prerelease to Stable Version Release" below.

**Note**: The new version header must be inserted **immediately after `## [Unreleased]`** (see Step 4). This ensures correct newest-first ordering of version headers.

### For Prerelease to Stable Version Release

When releasing from prerelease to a stable version (e.g., `v5.0.0.rc.2` -> `v5.0.0`), this is where the accumulated prerelease sections get coalesced into one stable section. **Curate carefully** — users landing on the stable version don't care about intermediate prerelease state, and noise here makes the upgrade story harder to read.

#### Step 1: Coalesce all prerelease sections into one stable section

- Replace `## [5.0.0.rc.0]`, `## [5.0.0.rc.1]`, `## [5.0.0.beta.1]`, etc. with a single `## [5.0.0] - YYYY-MM-DD` section
- **Move any remaining entries from `## [Unreleased]` into the new stable section** — anything still under `[Unreleased]` at stable-release time is shipping in this stable version. Leave `## [Unreleased]` with only its header (no entries).
- Combine entries from all prerelease sections and the moved `[Unreleased]` entries, consolidating duplicate category headings (e.g., merge multiple `### Fixed` sections into one under the preferred order from "Category Organization")
- Remove the orphaned compare links at the bottom of the file for the coalesced prerelease versions
- Add the `[5.0.0]` compare link pointing from the previous stable tag (e.g., `v4.2.0`) to `v5.0.0` — **not** from the latest RC tag
- Update the `[Unreleased]` compare link to point from `v5.0.0` to `HEAD`

#### Step 2: Curate the entries — REMOVE these

1. **Prerelease-only fixes** — bugs introduced during the prerelease cycle and fixed in a later RC. If the bug never shipped in a stable release, the fix is noise to stable users.
   - Investigate when a bug was introduced: `git log --oneline v<last_stable>..v<rc_that_fixed_the_bug>` — if this commit range doesn't contain the bug's introduction (i.e., the introducing commit predates the RC cycle), the bug was already in the last stable release and the fix belongs in the stable section. If the introduction *is* in this range, the bug never shipped in stable, so drop the fix.
   - Check the PR description for what was broken and when

2. **Refinements to prerelease-only features** — if a new feature was introduced in `rc.0` and then iterated in `rc.1`/`rc.2`, keep only the final description and drop the iteration history

3. **Internal/contributor-only tooling** — CI tweaks, build script changes, generator handling of prerelease version formats, local-dev tooling fixes. These don't belong in a user-facing changelog.

#### Step 3: Curate the entries — KEEP these

1. **User-facing fixes for bugs that existed in the previous stable** — if `rc.2` fixes a bug that was in `4.2.0`, that fix matters to stable users upgrading

2. **Compatibility fixes** — Ruby/Rails version support, dependency relaxations, etc.

3. **All breaking changes** — API/CLI changes, removed methods, configuration changes, exit code changes, generator output changes. Even if a breaking change was introduced and refined across multiple prereleases, the final breaking change description belongs in stable.

4. **Performance/security improvements affecting all users**

#### Step 4: Investigation process for each entry

For each entry from a prerelease section, ask:

- Was this bug present in the last stable release? If no, drop.
- Was this feature introduced in an earlier prerelease and then superseded? If yes, keep only the final state.
- Does this matter to someone upgrading from the last stable to this stable? If no, drop.

#### Step 5: Final read-through

Read the resulting stable section as if you're a user upgrading from the previous stable. Every entry should be something you'd want to know about. If an entry only makes sense to someone who tracked the RC cycle, drop it.

## Examples

Run this command to see real formatting examples from the codebase:

```bash
grep -B 1 -A 3 "^### " CHANGELOG.md | head -40
```

### Good Entry Example

```markdown
- Added the GitHub Actions flow generator and readiness checks for staging, review-app, and production-promotion workflows. [PR 278](https://github.com/shakacode/control-plane-flow/pull/278) by [Justin Gordon](https://github.com/justin808).
```

### Breaking Change Example

```markdown
- BREAKING CHANGE: `cpflow generate` now writes `bundle config set with 'production'` in the generated Dockerfile, dropping the previous `'staging production'` group set. Apps that placed gems specifically under a `staging:` group in their `Gemfile` (e.g. APM agents, observability libraries that should ship to staging) must move those gems into the `production:` group before regenerating, or the regenerated Dockerfile will exclude them at install time. New scaffolds are unaffected. [PR 278](https://github.com/shakacode/control-plane-flow/pull/278) by [Justin Gordon](https://github.com/justin808).
```

## Additional Notes

- Keep descriptions concise but informative
- Focus on the "what" and "why", not the "how"
- Use past tense for the description
- Be consistent with existing formatting in the changelog
- Always ensure the file ends with a trailing newline
- See `docs/releasing.md` for the full release process this command feeds into
