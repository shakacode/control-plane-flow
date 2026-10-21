# Shaka configuration

Shaka package / skill release: `0.1.0.pre.1`.

## Migration reference

This repo pins its Shaka reader source to the revision containing the [migration
procedure at `1a62cbcbe21da241668b2b108bc8588de4058aee`](https://github.com/shakacode/shaka/blob/1a62cbcbe21da241668b2b108bc8588de4058aee/skills/shaka/references/migration.md).
At that Shaka revision, `skills/shaka/lib/shaka/version.rb` defines the package
release and `docs/settings.md` documents the typed seam. The migration procedure
describes key changes, the two-step validation used for first adoption, and the
`seam upgrade` move to the `.agents/shaka/` layout this repository uses.

## Check configuration edits

Run from the repository root:

`shaka seam check --root . --local`

Checks the current checkout's YAML and fixed-script paths and executable bits. It
does not execute the wrappers and grants no trusted policy authority.
