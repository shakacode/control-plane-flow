# Secrets and ENV Values

You can store ENV values used by a container (within a workload) within Control Plane at the following levels:

1. Workload Container
2. GVC

For your "review apps," it is convenient to have simple ENVs stored in plain text in your source code. You will want to
keep some ENVs, like the Rails' `SECRET_KEY_BASE`, out of your source code. For staging and production apps, you will
set these values directly at the GVC or workload levels, so none of these ENV values are committed to the source code.

For storing ENVs in the source code, we can use a level of indirection so that you can store an ENV value in your source
code like `cpln://secret/my-app-review-env-secrets.SECRET_KEY_BASE` and then have the secret value stored at the org
level, which applies to your GVCs mapped to that org.

For setting up secrets, you'll need:

- **Org-level Secret:** This is where the values will be stored.
- **GVC Identity:** An identity that must be associated with each workload that requires access to the secret.
- **Org-level Policy:** A policy that binds the identity to the secret, granting the necessary permissions for the workload to access the secret.

You can do this during the initial app setup, like this:

1. Add the template for `app` to `.controlplane/templates`
2. Ensure that the `app` template is listed in `setup_app_templates` for the app in `.controlplane/controlplane.yml`
3. Run `cpflow setup-app -a $APP_NAME`
4. The secrets, secrets policy and identity will be automatically created, along with the proper binding
5. In the Control Plane console, upper left "Manage Org" menu, click on "Secrets"
6. Find the created secret (it will be in the `$APP_PREFIX-secrets` format) and add the secret env vars there
7. Use `cpln://secret/...` in the app to access the secret env vars (e.g., `cpln://secret/$APP_PREFIX-secrets.SOME_VAR`)

## Shared Secrets for Review Apps

Review apps often need access to a shared staging resource, such as one staging PostgreSQL workload or managed database.
Creating a database per pull request is expensive and slow, so you can create one shared org-level secret and policy,
then let each temporary review-app identity reveal that shared secret.

Create the shared dictionary secret and policy once in the staging org. The policy must target exactly the shared secret:

```yaml
kind: policy
name: my-app-review-database-secrets-policy
targetKind: secret
targetLinks:
  - //secret/my-app-review-database-secrets
```

Then declare the grant in the review app entry in `.controlplane/controlplane.yml`:

```yaml
apps:
  my-app-review:
    match_if_app_name_starts_with: true
    shared_secret_grants:
      - name: database
        secret_name: my-app-review-database-secrets
        policy_name: my-app-review-database-secrets-policy
```

Use the generated placeholder in templates instead of hardcoding the secret name:

```yaml
env:
  - name: DATABASE_URL
    value: cpln://secret/{{SHARED_SECRET_DATABASE}}.DATABASE_URL
```

`name` must be lower snake case. It becomes `{{SHARED_SECRET_<NAME>}}`, uppercased, in templates. `secret_name`
and `policy_name` must be Control Plane resource names: lowercase letters, numbers, and dashes only, starting and ending
with a letter or number.

`cpflow setup-app` still creates the per-app secret and policy for app-specific values, and also binds the app identity
to every configured shared policy. `cpflow deploy-image` repairs missing shared policy bindings before workloads are
updated, which helps existing review apps recover after the config is added. `cpflow delete` and `cpflow cleanup-stale-apps`
remove those shared policy bindings when a review app is deleted.

For shared databases, keep runtime data isolated by using a per-review-app database name, schema, or tenant key. A common
pattern is to keep the host, user, and password in the shared secret, then have `hooks.post_creation` create the
PR-specific database/schema. Avoid a generic `hooks.pre_deletion` that drops the database: `cpflow delete` runs the
pre-deletion hook before it removes the app workloads, so live connections can make PostgreSQL reject the drop. Stop the
review app workloads first, or run cleanup from trusted admin automation against the shared Postgres workload. See
[Share One Control Plane Postgres for Staging and Review Apps](tips.md#share-one-control-plane-postgres-for-staging-and-review-apps)
for the full pattern.

Here are the manual steps for reference. We recommend that you follow the steps above:

1. In the upper left of the Control Plane console, "Manage Org" menu, click on "Secrets"
2. Create a secret with `Secret Type: Dictionary` (e.g., `my-secrets`) and add the secret env vars there
3. In the upper left "Manage GVC" menu, click on "Identities"
4. Create an identity (e.g., `my-identity`)
5. Navigate to the workload that you want to associate with the identity created
6. Click "Identity" on the left menu and select the identity created
7. In the lower left "Access Control" menu, click on "Policies"
8. Create a policy with `Target Kind: Secret` and add a binding with the `reveal` permission for the identity created
9. Use `cpln://secret/...` in the app to access the secret env vars (e.g., `cpln://secret/my-secrets.SOME_VAR`)
