# PostgreSQL for disposable review apps

Use the generated `.controlplane/templates/postgres.yml` for a PostgreSQL workload
that belongs to one disposable review app. For production database migration, see
[Migrating PostgreSQL from Heroku to RDS](./postgres.md).

## Enable cleanup for new review apps

The generated template marks three helper resources:

| Resource | Purpose |
| --- | --- |
| `<APP>-pg` | Credential dictionary |
| `<APP>-pg-script` | Initialization-script secret |
| `<APP>-pg-access` | Policy granting access to those secrets |

Each helper template carries this tag:

```yaml
tags:
  cpflow-disposable-postgres-app: "{{APP_NAME}}"
```

`cpflow apply-template` retains the tag for dynamically named review apps and removes
it for persistent apps. In an existing project, add the tag to all three helper
**templates before creating new review apps**. Reapplying a marked template to an
existing unmarked resource is refused; it does not adopt that resource.

Before opting in, check that your deployment token can:

- Read and delete the three helper resources.
- Read each secret's effective access report (`viewAccessReport` on the org).

A missing or incomplete access report blocks cleanup before app data is deleted.

## Delete an app

Run the normal app deletion command:

```sh
cpflow delete -a APP_NAME
```

Cleanup validates the helpers before deleting app data. It removes the marked
policy and secrets before deleting the GVC. Deleting a single workload with
`cpflow delete -a APP_NAME -w WORKLOAD_NAME` preserves the helpers.

The ownership checks require:

- The same app marker on every surviving helper.
- A policy targeting exactly the two helper secrets.
- Only `reveal` grants in that policy, for the app and PostgreSQL identities in the
  app's GVC.
- No helper listed in `shared_secret_grants`.
- No effective secret access through another application policy or identity.

Reapplying marked helpers with `cpflow apply-template` uses the same checks.

## Understand a cleanup refusal

Cleanup preserves resources when a marker, policy, or access report cannot establish
exclusive ownership. A refusal aborts whole-app deletion before live app data is
deleted. Fix the reported condition before retrying; do not remove a
sharing grant until you know which applications depend on it.

| Condition | Result |
| --- | --- |
| All helpers are unmarked legacy resources | App deletion proceeds; helpers are preserved |
| Marked and unmarked helpers coexist | Cleanup refuses deletion |
| A marker names another app | Cleanup refuses deletion |
| Policy targets or principals differ from the expected app scope | Cleanup refuses deletion |
| A helper is configured as shared | Cleanup refuses deletion |
| Secret access reports are unavailable or incomplete | Cleanup refuses deletion |

The access checks include permissions implied by `edit` or `manage`. Global `manage`
grants to org groups, users, or service accounts count as org administration.
Targeted or query grants, and grants to other GVC identities, block cleanup.

For shared staging credentials, use the
[shared-secret configuration guide](./secrets-and-env-values.md#shared-secrets-for-review-apps)
instead of marking them as disposable helpers.

## Recover after interruption

Repeat `cpflow delete` with the same app name. Cleanup tolerates an already absent
GVC, policy, or secret and rechecks the surviving helpers before deleting them.

Unmarked legacy helpers need manual cleanup after you establish that no other app
uses them. Rolling back to an older cpflow version leaves the tags in place but
stops automatic helper cleanup.
