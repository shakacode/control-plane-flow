# Connecting Control Plane workloads to a private AWS RDS/Aurora database

Control Plane (CPLN) does not offer a managed Postgres service. For production Postgres on AWS, the typical setup
is **Amazon RDS** (or **Aurora**) in a **private VPC subnet**, reached from CPLN workloads over a private network
path — not the public internet.

This guide covers the recommended setup: **CPLN Cloud Wormhole via an Agent**.

> **Sourcing note.** Field names, schema, and limits in this guide are sourced from the public Control Plane
> documentation at <https://shakadocs.controlplane.com> as of May 2026. The YAML and CLI snippets
> below have not been end-to-end verified against a live org. Before applying in production, sanity-check the
> exact field names with `cpln agent get <name> -o yaml` and `cpln identity get <name> -o yaml` against your own
> org, and consult `cpln <command> --help` for the latest CLI flags.

## Why private networking

- **Security.** The database stays in private subnets with no public IP and no Internet Gateway egress. Inbound
  traffic to the DB only comes from a specific security group inside your VPC — never the public internet.
- **Compliance.** SOC 2, HIPAA, and most internal security reviews expect "no publicly addressable database."
- **Stable allowlists.** No need to maintain CPLN egress IP allowlists on the RDS security group as CPLN's
  infrastructure evolves — the Agent runs inside *your* VPC.
- **Cost.** No NAT or data-egress fees for in-region database traffic when the Agent is in the same region as RDS.

If you only need RDS for **development/test** review apps and don't care about exposing it publicly, see the
[Database section of the README](../README.md#database) for the simpler "public RDS + security-group allowlist"
pattern. Don't run a production database that way.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            Control Plane (CPLN)                              │
│                                                                              │
│   ┌──────────────┐         ┌──────────────────────┐                          │
│   │   Workload   │ ──────► │       Identity       │                          │
│   │  (rails app) │         │   networkResources:  │                          │
│   │              │         │     - name: db-prod  │                          │
│   │  DATABASE_URL│         │       FQDN: db.rds…  │                          │
│   │  = postgres://         │       resolverIP:    │                          │
│   │    user:pwd@           │         10.0.0.2     │                          │
│   │    db-prod:5432/myapp  │       ports: [5432]  │                          │
│   │                        │       agentLink:     │                          │
│   │                        │         //agent/vpc1 │                          │
│   └──────────────┘         └──────────┬───────────┘                          │
│                                       │                                      │
│                            Wormhole (encrypted)                              │
└───────────────────────────────────────┼──────────────────────────────────────┘
                                        │  outbound TLS, agent-initiated
┌───────────────────────────────────────▼──────────────────────────────────────┐
│                          Your AWS VPC (e.g. us-east-2)                       │
│                                                                              │
│   ┌─────────────────────────────────┐         ┌─────────────────────────┐    │
│   │  Auto Scaling Group (Agents)    │  ────►  │   RDS / Aurora cluster  │    │
│   │  - 2× EC2 (t3.small+)           │  5432   │   private subnets only  │    │
│   │  - Ubuntu 24.04 LTS             │         │   SG: allow from agent  │    │
│   │  - SG: egress to RDS SG:5432    │         │   SG only               │    │
│   └─────────────────────────────────┘         └─────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────────┘
```

Key properties:

- The Agent **dials out** to CPLN over TLS. No inbound from CPLN to your VPC is required, so RDS stays fully
  private.
- The workload connects to the resource by its **name**, not by RDS's hostname — CPLN routes the connection
  through the agent.
- The Agent is **org-scoped** — one agent can serve workloads in any GVC in the org.
- The Identity (and its `networkResources`) is **GVC-scoped** — an org with staging and production GVCs
  needs the same `networkResources` declared in each GVC's identity, but can share a single agent.

## Prerequisites

- An AWS account with:
  - A VPC with at least one **private subnet** for RDS and at least one **subnet with outbound internet access**
    for the agent ASG (the agent needs to reach CPLN; this is typically a public subnet or a private subnet
    behind a NAT gateway).
  - An RDS or Aurora cluster in the private subnets, with a security group you can edit.
  - IAM permissions to create launch templates, ASGs, and security groups.
- A Control Plane org where you have the **`agent.create`**, **`identity.edit`**, and **`workload.edit`**
  permissions.
- `cpln` CLI installed and authenticated against the target org.

## Step 1 — Create the Agent in the CPLN UI

The CPLN UI generates a bootstrap script containing the agent's credentials. You'll paste this into the EC2
launch template's user data in step 2.

1. In the CPLN UI, go to **Agents** → **New**.
2. Give it a stable name (e.g. `aws-us-east-2-prod`). The org-scoped link will be
   `//agent/aws-us-east-2-prod`.
3. Pick **AWS** as the platform.
4. Copy the **bootstrap script** displayed by the UI. Treat it like a secret — it contains a one-time
   registration token.

> Alternative declarative form using YAML:
>
> ```sh
> cat > agent.yaml <<'YAML'
> kind: agent
> name: aws-us-east-2-prod
> description: Wormhole agent in customer AWS VPC, us-east-2.
> YAML
> cpln apply --file agent.yaml
> ```
>
> The bootstrap token is shown by the UI immediately after creation and is **not retrievable
> afterward** — if you miss it, delete the agent and recreate it. The closest CLI equivalents are
> `cpln agent info <name>` (operational info, not the bootstrap) and `cpln agent manifest`
> (consumes an existing bootstrap file, doesn't issue one). For IaC workflows that need a fresh
> token without the UI, capture the output of `cpln agent create` (which issues the bootstrap as
> part of creation) into your secrets store on the same run; you won't get a second chance.

## Step 2 — Launch the Agent on AWS

Recommended baseline:

- **AMI:** Ubuntu Server 24.04 LTS.
- **Instance type:** `t3.small` for testing; `t3.medium` or larger for production (CPLN recommends a minimum of
  2 vCPU / 4 GiB).
- **Launch Template:** set the user data to the bootstrap script from step 1.
  - **Security note:** EC2 user data is visible to anyone with `ec2:DescribeLaunchTemplates` /
    `ec2:DescribeInstanceAttribute`, and readable from the instance itself at
    `http://169.254.169.254/latest/user-data` via IMDS. For production, prefer storing the bootstrap script
    in AWS Secrets Manager or SSM Parameter Store and having a small bootstrap snippet in user data fetch
    and execute it at startup (granting the instance role `secretsmanager:GetSecretValue` or `ssm:GetParameter`
    on that specific resource ARN). At minimum, audit who has those `Describe*` permissions in the account.
- **Auto Scaling Group:**
  - Testing: desired 1 / min 1 / max 1.
  - Production: desired 2 / min 2 / max 4 across at least two availability zones. Two agents give you
    a rolling-restart path during upgrades and survive a single-AZ outage.
- **Subnets:** subnets must have outbound internet access (public subnet with auto-assign IPv4, or private
  subnet with NAT). The agent dials CPLN over TLS; it does *not* need any inbound rule from the internet.

After the ASG is healthy, verify the agent registered:

1. CPLN UI → **Agents** → select your agent → a green heartbeat should appear within 2–3 minutes.
2. Or: `cpln agent get aws-us-east-2-prod -o yaml` and look for a recent `lastModified` / status.

## Step 3 — Security groups

Two security groups. The RDS rule is the obvious one, but the agent also needs outbound paths for
CPLN control-plane TLS and DNS, otherwise it can register-but-not-resolve (or fail to register at
all) even when the DB rule is correct:

- **Agent SG** (attached to the ASG instances):
  - Egress to the **RDS SG** on port `5432` (or `3306` for MySQL) — the database traffic itself.
  - Egress to `0.0.0.0/0` on **TCP `443`** — the agent dials out to CPLN over TLS to register and
    tunnel traffic. If your environment forbids `0.0.0.0/0`, restrict to your CPLN region's
    documented egress endpoints (or route via a NAT gateway / egress proxy with that allowlist).
  - Egress to the **VPC DNS resolver** on **UDP/TCP `53`** — required when `networkResources` uses
    `FQDN` + `resolverIP` so the agent can resolve the cluster endpoint. The VPC `.2` resolver lives
    inside the VPC, so this is typically already permitted by default egress; lock it down to the
    resolver IP if your default egress is restrictive.
- **RDS SG** (attached to the DB cluster): ingress from the Agent SG on port `5432`.

```text
Agent SG egress    ──►  RDS SG       port 5432    (database)
Agent SG egress    ──►  0.0.0.0/0    TCP  443     (CPLN control plane)
Agent SG egress    ──►  VPC .2 DNS   UDP/TCP 53   (FQDN resolution)
RDS SG  ingress    ◄──  Agent SG     port 5432
```

Reference the agent SG by ID, not by CIDR. That way, the rule stays correct as ASG instances are recycled.

## Step 4 — Declare the Network Resource on the Identity

cpflow already provisions one Identity per workload (used for binding secrets — see
`{{APP_IDENTITY_LINK}}` in `templates/rails.yml`). We need to add a `networkResources` entry to **that
existing identity**, not create a new one.

> **Important: `cpln apply` is a full replace, not a merge.** Applying a stripped-down identity YAML
> that only contains `networkResources` will silently drop any other fields already set on the
> identity (tags, description, and any previously configured `networkResources`). Always **export
> the live identity first**, edit it in place, then re-apply. (Policy bindings themselves live on
> the Policy resource — not on the identity — so applying the identity won't touch them, but the
> verification step below still checks the policy → identity link in case anything else recreated it.)

First, find the identity name. cpflow's `Config#identity` defines this as `<app>-identity` and the
`{{APP_IDENTITY}}` template variable expands to the same — so for an app named `my-app-production` the
identity is `my-app-production-identity`. Confirm against your org (the `cpln` CLI exposes `get` and
`query` for identities — there is no `list` subcommand):

```sh
# `get` with no ref returns all identities in the GVC.
cpln identity get --gvc my-app-production --org my-org

# Or, to filter by name property:
cpln identity query --gvc my-app-production --org my-org \
  --property name=my-app-production-identity
```

Export it and add the `networkResources` block. Look up your VPC's DNS resolver IP (typically the VPC CIDR
base + 2, e.g. `10.0.0.2` for a `10.0.0.0/16` VPC) and your RDS cluster endpoint:

```sh
# Replace my-app-production-identity with whatever `cpln identity get` shows for your app.
cpln identity get my-app-production-identity \
  --gvc my-app-production --org my-org -o yaml > identity-db.yaml
```

Edit `identity-db.yaml` and **append** the `networkResources` block — keep every other field exactly as
exported:

> ⚠️ **Verify field casing against your org before applying.** The field names below (`FQDN`, `IPs`,
> `agentLink`, `resolverIP`) are sourced from public CPLN docs. If the live API uses different casing,
> `cpln apply` will accept the file but silently ignore the resource — workloads will hit
> `could not translate host name` with no obvious link to the identity YAML. Diff your edited file
> against the original export from `cpln identity get` to confirm.

```yaml
# identity-db.yaml (after edit — abbreviated, your file will have more fields)
kind: identity
name: my-app-production-identity   # output of `cpln identity get` for your app
description: ...                   # leave existing description alone
# … any other existing fields stay as-is …
networkResources:
  - name: db-primary           # ← workload connects to this hostname
    agentLink: //agent/aws-us-east-2-prod
    FQDN: myapp-prod.cluster-xxxxx.us-east-2.rds.amazonaws.com
    resolverIP: 10.0.0.2       # your VPC's .2 resolver, reachable from the agent
    ports:
      - 5432
  # Optional second resource for Aurora reader endpoint:
  - name: db-readers
    agentLink: //agent/aws-us-east-2-prod
    FQDN: myapp-prod.cluster-ro-xxxxx.us-east-2.rds.amazonaws.com
    resolverIP: 10.0.0.2
    ports:
      - 5432
```

If you'd rather pin to specific IPs instead of an FQDN, swap `FQDN` + `resolverIP` for an `IPs:` array of
1–5 IPv4 addresses. See [IPs vs FQDN](#ips-vs-fqdn--which-to-use) below for trade-offs.

Apply it back:

```sh
cpln apply --file identity-db.yaml --gvc my-app-production --org my-org
```

(Use whatever `--org` / `--gvc` flags your team uses, or rely on the org/GVC defaults set by `cpln profile`.)

Confirm the identity now has the new `networkResources` and that the policy still references it:

```sh
# 1. The identity itself should now list `networkResources`.
cpln identity get my-app-production-identity --gvc my-app-production --org my-org -o yaml \
  | grep -A 5 networkResources

# 2. Policies are separate resources — they reference the identity by link, not by replacing it.
#    Confirm the existing cpflow-generated policy (typically <app>-secrets) still grants
#    `reveal` on the workload's secrets to this identity. The full identity link cpflow uses is
#    /org/<org>/gvc/<app>/identity/<app>-identity (see Config#identity_link).
#    (The `cpln` CLI exposes `policy get`/`policy query` — there is no `policy list` subcommand.)
cpln policy get --org my-org -o yaml \
  | grep -B 1 -A 8 "/org/my-org/gvc/my-app-production/identity/my-app-production-identity"
```

If the policy block is gone or no longer contains the identity link, your workload won't be able to read
its secrets — re-bind the identity to the secrets policy directly with the CPLN CLI:

```sh
cpln policy add-binding my-app-production-secrets-policy --org my-org \
  --identity /org/my-org/gvc/my-app-production/identity/my-app-production-identity \
  --permission reveal
```

This is the same call `cpflow setup-app` makes internally (see `Controlplane#bind_identity_to_policy`).
`cpflow apply-template app` does **not** recreate the binding — its `app` template only defines the
GVC, and `--add-app-identity` only inserts an identity object, not the policy binding. Adjust the
policy name if you've overridden `secrets_policy_name` in `controlplane.yml`.

Schema notes (per CPLN's documented `networkResources` schema):

- `name` — the hostname the workload will use. Pick something short and stable (`db-primary`, `db-readers`).
- `agentLink` — `//agent/<agent-name>` (org-scoped).
- Exactly one of `IPs` or `FQDN` is required per resource:
  - `IPs` — array of **1 to 5** IPv4 addresses. The agent routes to exactly those IPs.
  - `FQDN` — a fully qualified domain name. Requires `resolverIP` to also be set so the agent knows which
    DNS server to ask.
- `resolverIP` — IPv4 of a DNS server reachable from the agent (typically the VPC's `.2` resolver, e.g.
  `10.0.0.2`).
- `ports` — array of **1 to 10** ports, each `0–65535`. Required.
- One identity may declare **up to 50** `networkResources`.
- For native AWS PrivateLink, an alternative `awsPrivateLink` field exists on identities (see
  [Alternatives](#alternatives--when-not-to-use-an-agent) below).

### IPs vs FQDN — which to use?

- **FQDN** (recommended for Aurora and any RDS cluster with failover): set `FQDN` to the cluster endpoint
  and `resolverIP` to the VPC's `.2` resolver. The agent re-resolves on connect, so there is no identity
  change required on failover — but plan for the full 60–120 s window (failure detection, replica
  promotion, DNS update, propagation), not just Aurora's ~30 s DNS TTL. See
  [Aurora failover](#aurora-failover) in Operations.
- **IPs** (only when you control the target's IP stability): a single-instance RDS that you don't expect to
  recycle, or a static private IP behind a network appliance. The agent will route to exactly those IPs
  — if RDS recycles the underlying instance and the IP changes, you must update the identity manually.

For most ShakaCode setups, use FQDN. The IPs form is shown here mainly to make the schema concrete and for
the rare case where you want to pin to a specific IP.

## Step 5 — Point the workload at the resource

The workload's `DATABASE_URL` uses the **resource `name`** as the hostname, not the RDS endpoint.

CPLN's `cpln://secret/<name>.<key>` syntax substitutes the **entire env var value** at workload startup — it
is not a substring interpolation. So you have two options for assembling a `DATABASE_URL` that includes a
secret password:

**TLS to RDS:** RDS and Aurora require TLS by default in current parameter groups. Always include
`sslmode=require` (or stricter — `verify-ca` / `verify-full` if you bundle the AWS RDS CA bundle) in the
connection string or `database.yml`. Without it, newer clusters will refuse the connection and older ones
will silently fall back to unencrypted.

**Option A: store the full URL in a secret (simpler).** Recommended for production where the DB credentials
rarely change.

Create a dictionary secret holding the entire connection string. **Use the CPLN UI** (Secrets → New
dictionary secret) — it's the safest place to enter credentials and avoids shell history, tty echo, and
plaintext request bodies entirely.

> ⚠️ **CLI form below is reference-only.** It writes credentials to your shell history and to the `cpln`
> request body in plaintext. The common "prefix with a space" trick only works when `HISTCONTROL` includes
> `ignorespace` or `ignoreboth`, which is **not** set by default on many stripped-down bastion/EC2 shells.
> Prefer the UI for any real credential.

```sh
# Reference only — prefer the UI.
cpln apply --file - <<'YAML'
kind: secret
name: my-app-database
type: dictionary
data:
  url: "postgres://app:supersecret@db-primary:5432/myapp_production?sslmode=require"
  url_readers: "postgres://app_readonly:readsecret@db-readers:5432/myapp_production?sslmode=require"
YAML
```

Make sure the existing app policy grants `reveal` on this new secret — see
[secrets-and-env-values.md](./secrets-and-env-values.md).

Then in your workload template:

```yaml
# In your rails.yml workload template
spec:
  containers:
    - name: rails
      env:
        - name: DATABASE_URL
          value: cpln://secret/my-app-database.url
        # Optional, for read replicas:
        - name: DATABASE_REPLICA_URL
          value: cpln://secret/my-app-database.url_readers
```

**Option B: keep the password in a secret, assemble the URL in app code.** Use this if you want the URL host
to live in plaintext config so it's easy to grep for in templates.

Create a secret holding just the password. Again, **prefer the CPLN UI** to enter the credential; the
CLI heredoc below is reference-only (same shell-history caveat as Option A).

```sh
# Reference only — prefer the UI.
cpln apply --file - <<'YAML'
kind: secret
name: my-app-database
type: dictionary
data:
  password: "supersecret"
YAML
```

Then set the workload env:

```yaml
env:
  - name: DATABASE_HOST
    value: db-primary
  - name: DATABASE_PORT
    value: "5432"
  - name: DATABASE_NAME
    value: myapp_production
  - name: DATABASE_USER
    value: app
  - name: DATABASE_PASSWORD
    value: cpln://secret/my-app-database.password
```

…and in `config/database.yml`:

```yaml
production:
  adapter: postgresql
  host: <%= ENV.fetch("DATABASE_HOST") %>
  port: <%= ENV.fetch("DATABASE_PORT") %>
  database: <%= ENV.fetch("DATABASE_NAME") %>
  username: <%= ENV.fetch("DATABASE_USER") %>
  password: <%= ENV.fetch("DATABASE_PASSWORD") %>
  sslmode: require
```

Either way:

- `db-primary` / `db-readers` are the `networkResources[].name` values from step 4 and serve as the
  workload-facing hostnames per the CPLN docs.
- If your workload can't resolve `db-primary`, diagnose with
  `cpln workload exec <workload> -- nslookup db-primary`. The Verification section below covers the
  most common resolution and connectivity failures.

## Step 6 — Bind the identity to the workload

The wormhole only takes effect once the workload's `spec.identityLink` points at the identity from step 4.
cpflow's stock templates already do this — see `{{APP_IDENTITY_LINK}}` in `templates/rails.yml`,
`templates/sidekiq.yml`, and `templates/daily-task.yml`:

```yaml
# templates/rails.yml (excerpt)
spec:
  # Identity is used for binding workload to secrets — and, after step 4, also to network resources.
  identityLink: {{APP_IDENTITY_LINK}}
```

If you're using the cpflow templates as-is, no change is needed here — re-applying the templates
(`cpflow apply-template rails -a my-app-production` etc.) is enough. If you wrote a custom workload without
that line, add it now. The most reliable way to set `identityLink` on an existing workload is the same
export-edit-apply loop used in Step 4: `cpln workload get <name> --gvc <gvc> -o yaml > workload.yaml`,
edit `spec.identityLink`, then `cpln apply --file workload.yaml`. (`cpln workload update --help` may also
list a `--set` flag for this; verify against your installed CLI version before relying on it.)

Re-apply the workload template:

```sh
cpflow apply-template rails -a my-app-production
```

## Verification

Open an interactive shell in a one-off copy of the rails workload (with the identity, env, and image of
the live workload), then run `psql` from inside it. `cpflow run` flattens argv with `join(" ")` and does
no shell escaping (see `lib/command/base.rb`), so quoted multi-arg commands like
`-- bash -c 'psql "$DATABASE_URL" -c "select 1"'` won't survive round-tripping — running `psql` from
inside the interactive shell sidesteps the issue entirely.

```sh
# Step 1: open a one-off interactive shell inside the rails workload.
cpflow run -a my-app-production

# Step 2: from inside the workload shell, confirm DATABASE_URL is set and reachable.
echo "$DATABASE_URL"
psql "$DATABASE_URL" -c 'select now(), version();'
```

Expected: a current timestamp and the RDS Postgres version. Common failures:

- `could not translate host name "db-primary" to address` — usually one of:
  - The identity isn't bound to the workload: check `spec.identityLink` on the workload, re-apply the
    template, and re-run.
  - The workload was running **before** you added `networkResources` to the identity: existing replicas
    don't pick up identity changes automatically. Recycle the workload (`cpln workload force-redeployment`
    or re-apply the template) so new replicas start with the updated network resource map.
  - Some runtimes need the GVC-suffixed form. If the bare `db-primary` won't resolve, try
    `db-primary.<gvc>.cpln.local` (e.g. `db-primary.my-app-production.cpln.local`) in `DATABASE_URL` and
    `database.yml` before assuming the identity is wrong.
- `connection refused` or timeouts to the resource — the agent → RDS path is wrong. Verify the agent has a
  green heartbeat in the CPLN UI, the agent SG has egress to the RDS SG on `5432`, and the RDS SG accepts
  ingress from the agent SG.
- `FATAL: no pg_hba.conf entry … SSL off` or `SSL connection is required` — `sslmode=require` is missing
  from the connection string or `database.yml`.

## Operations

### High availability

- Run **at least 2 agents** in the ASG in production. Agent upgrades are rolling, and a single agent is a
  single point of failure for *all* private connectivity from the GVC.
- Spread the ASG across at least 2 availability zones.

### Aurora failover

- With **IPs** in `networkResources`: failover swaps which underlying instance the writer endpoint resolves
  to. The IPs you've allowlisted may now point at the wrong instance. For Aurora specifically, prefer the
  **FQDN** form so the agent re-resolves on each connect.
- With **FQDN**: the agent re-resolves the cluster endpoint. Aurora's DNS TTL is ~30 seconds, but the full
  failover window (detection → replica promotion → DNS update → propagation to your VPC resolver) is
  typically **60–120 seconds** in practice. Size connection-pool timeouts and circuit breakers for the
  upper end of that range, not just the DNS TTL.
- Either way, the Rails connection pool will see a burst of errors during failover. The app should be
  configured to reconnect cleanly on `PG::ConnectionBad` and similar errors. Test failover behavior
  before assuming the app recovers without intervention.

### Agent sizing and upgrades

- The CPLN agent process (not the NIC) is the typical throughput bottleneck. AWS `t3.small` provides up
  to ~5 Gbps burst network bandwidth (≥250 Mbps baseline), which handles normal app database traffic
  comfortably. Watch agent CPU and active connection count and scale up the instance type if CPU stays
  above ~70% or connection-queue latency rises.
- CPLN occasionally publishes new agent versions. The ASG + bootstrap script combination handles upgrades
  by re-rolling instances; let it do that during low-traffic windows.

### Cost

- Two `t3.small` instances 24/7 in `us-east-2`: ~$30/month.
- Cross-AZ data transfer between agent and RDS: typically negligible for normal app traffic; significant
  for bulk loads (consider placing the agent in the same AZ as the RDS writer for big migrations).

## Alternatives — when not to use an Agent

The Agent approach is universal: works for any TCP target in any private network. Two CPLN-native
alternatives are worth knowing about:

- **AWS PrivateLink (`awsPrivateLink` on identity).** If your AWS team is willing to publish the database
  behind a Network Load Balancer + VPC Endpoint Service, you can skip the Agent entirely and have CPLN
  consume the endpoint service natively. Fewer moving parts to operate, but more AWS-side setup
  (NLB + target group + endpoint service + permissions). Recommended when you're already standardized on
  PrivateLink for other services.
- **Public RDS with a tight security-group allowlist.** Acceptable for dev/test review apps only. CPLN
  workload egress IPs are not stable in the long term, so this approach is brittle for production.

## See also

- [Migrating Postgres database from Heroku infrastructure](./postgres.md) — covers Bucardo migration, which
  still applies once the target RDS is reachable via the agent.
- [Secrets and env values](./secrets-and-env-values.md) — how `cpln://secret/...` references resolve.
- [README: Database](../README.md#database) — high-level options including dev/test public RDS.
- [Control Plane: Agent reference](https://shakadocs.controlplane.com/reference/agent).
- [Control Plane: Create an Identity guide](https://shakadocs.controlplane.com/guides/create-identity).
- [Control Plane: Setup Agent on AWS](https://shakadocs.controlplane.com/guides/setup-agent).
- [AWS: Scenarios for accessing a DB instance in a VPC](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_VPC.Scenarios.html).
