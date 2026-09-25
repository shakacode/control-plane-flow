# Shaka configuration

Shaka package / skill release: `0.1.0.pre.1`.

## Migration reference

This repo pins its Shaka reader source to the revision containing the [migration
procedure at `8431a718cfd91e9ce7cb4276baae076848e05d13`](https://github.com/shakacode/shaka/blob/8431a718cfd91e9ce7cb4276baae076848e05d13/skills/shaka/references/migration.md).
At that Shaka revision, `skills/shaka/lib/shaka/version.rb` defines the package
release and `docs/settings.md` documents the typed seam. The migration procedure
describes key changes and the two-step validation used for first adoption.

## Check configuration edits

Run from the repository root:

`shaka seam check --root . --local`

Checks the current checkout's YAML and fixed-script paths and executable bits. It
does not execute the wrappers and grants no trusted policy authority.
