# Shared Secret Grants

## Goal

Let review apps intentionally reveal shared Control Plane secrets, such as a shared staging database secret, without hardcoding the base app secret name or manually patching each generated review app identity.

## Design

- Add `shared_secret_grants` to each app entry in `.controlplane/controlplane.yml`.
- Each grant has a stable `name`, a `secret_name`, and a `policy_name`.
- Template files can use `{{SHARED_SECRET_<NAME>}}` to reference the shared secret name.
- `setup-app` binds the app identity to the app secret policy and every configured shared secret policy.
- `deploy-image` repairs missing shared policy bindings before running a release script or updating workloads, so existing review apps recover on the next deploy.
- `delete` unbinds the app identity from the app secret policy and every configured shared secret policy when the identity and policy still exist.
- `cleanup-stale-apps` keeps delegating deletion to `cpflow delete`, so stale review apps get the same unbinding behavior.

## Verification

- Add config specs for default, normalization, and validation.
- Add template specs for shared placeholder substitution.
- Add setup/deploy/delete unit specs for binding and unbinding shared policies.
- Update user docs and generated command docs.
- Run targeted specs, command-doc checks, and full verification as practical before publishing the PR.
