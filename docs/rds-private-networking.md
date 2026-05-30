# Connecting Control Plane workloads to a private AWS RDS/Aurora database

Control Plane (CPLN) does not offer a managed Postgres service. For production Postgres on AWS, the typical setup
is **Amazon RDS** (or **Aurora**) in a **private VPC subnet**, reached from CPLN workloads over a private network
path — not the public internet.

This guide covers the recommended setup: **CPLN Cloud Wormhole via an Agent**.

> **Sourcing note — verify field casing before you apply.** Field names, schema, and limits in this guide
> are sourced from the public Control Plane documentation at <https://shakadocs.controlplane.com> as of
> May 2026 and have **not** been end-to-end verified against a live org. This matters because a casing
> mismatch **fails silently**: `cpln apply` accepts the file, ignores the unrecognized field, and the
> workload then can't reach the database — with no error pointing back to the YAML. Before applying in
> production, diff your edited files against a fresh `cpln identity get <name> -o yaml-slim` (and
> `cpln agent get <name> -o yaml`) export to confirm the exact field names, and consult
> `cpln <command> --help` for the latest CLI flags.

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

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                            Control Plane (CPLN)                              │
│                                                                              │
│   ┌──────────────┐         ┌──────────────────────┐                          │
│   │   Workload   │ ──────► │       Identity       │                          │
│   │  (rails app) │         │   networkResources:  │                          │
│   │              │         │   - name: db-primary │                          │
│   │  DATABASE_URL│         │       FQDN: db.rds…  │                          │
│   │  = postgres://         │       resolverIP:    │                          │
│   │    user:pwd@           │         10.0.0.2     │                          │
│   │    db.rds…:5432/myapp  │       ports: [5432]  │                          │
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
│   │  - 2× EC2 (t3.medium+ prod)     │  5432   │   private subnets only  │    │
│   │  - Ubuntu 24.04 LTS             │         │   SG: allow from agent  │    │
│   │  - SG: egress to RDS SG:5432    │         │   SG only               │    │
│   └─────────────────────────────────┘         └─────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────────┘
```

Key properties:

- The Agent **dials out** to CPLN over TLS. No inbound from CPLN to your VPC is required, so RDS stays fully
  private.
- Traffic through the wormhole is **encrypted in transit** — the agent uses WireGuard for the tunnel between
  your VPC and CPLN.
- The workload reaches the resource through the wormhole. For a **TLS** database like RDS/Aurora, connect by
  the cluster's **FQDN** (the real endpoint) so the certificate matches; CPLN routes that FQDN through the
  agent because it's declared in `networkResources`. The short `name` is the resource's identifier — usable
  as the host only for non-TLS targets.
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

## Step 1 — Create the Agent and AWS user-data script

The CPLN UI first generates a **bootstrap config** for the agent, then uses that config to generate the
cloud-provider script. For AWS, the EC2 Launch Template needs the generated **Userdata Script** — not the
raw bootstrap config JSON.

1. In the CPLN UI, go to **Agents** → **New**.
2. Give it a stable name (e.g. `aws-us-east-2-prod`). The org-scoped link will be
   `//agent/aws-us-east-2-prod`.
3. Pick **AWS** as the platform.
4. Click **Create**, then save the bootstrap config JSON manually or with **Download Config File**.
   Treat this like a secret. It is not retrievable after you close the modal — if you lose it, delete
   the agent and recreate it.
5. Click **Next** and copy or download the AWS **Userdata Script**. This is the script you paste into the
   EC2 Launch Template in step 2.

If you already created the agent but still have the bootstrap config, open the agent's page, choose
**Actions** → **Download Scripts**, paste/import the bootstrap config, and copy the YAML from the
**Userdata Script** tab.

> **CLI creation note:** do not use `cpln apply --file agent.yaml` for this step. It can create the
> Agent object, but it does not produce the bootstrap config needed by the EC2 host. Use the Console
> path above, or use `cpln agent create` and capture stdout to a bootstrap config file:
>
> ```sh
> cpln agent create \
>   --name aws-us-east-2-prod \
>   --description "Wormhole agent in customer AWS VPC, us-east-2." \
>   --org my-org > bootstrap-config.json
> ```
>
> Do not paste `bootstrap-config.json` directly into EC2 user data. Render an AWS Userdata Script from
> that config first (Console **Download Scripts**, or a CLI/scripted equivalent that you have verified
> in your org), then use the rendered script in the Launch Template.

## Step 2 — Launch the Agent on AWS

Recommended baseline:

- **AMI:** Ubuntu Server 24.04 LTS.
- **Instance type:** `t3.small` for testing; `t3.medium` or larger for production (CPLN recommends a minimum of
  2 vCPU / 4 GiB). In practice the binding constraint is **network bandwidth**, not CPU/RAM, so size on the
  instance's *baseline* (not burst) bandwidth for your expected DB throughput. The agent ships in both Intel
  (x86-64) and ARM (Graviton) builds, so ARM families cost less for the same capability — use `t4g` for
  burstable workloads (e.g. `t4g.medium` in place of `t3.medium`) and `c7g`/`c6g` when you need sustained
  bandwidth at higher load.
- **Launch Template:** set the user data to the AWS **Userdata Script** generated in step 1.
  - **Security note:** EC2 user data is visible to anyone with `ec2:DescribeLaunchTemplates` /
    `ec2:DescribeInstanceAttribute`, and readable from the instance itself at
    `http://169.254.169.254/latest/user-data` via IMDS. For production, prefer storing the generated
    Userdata Script (or the bootstrap config plus a verified render step) in AWS Secrets Manager or SSM
    Parameter Store and having a small bootstrap snippet in user data fetch and execute it at startup
    (granting the instance role `secretsmanager:GetSecretValue` or `ssm:GetParameter` on that specific
    resource ARN). That requires an IAM instance profile: create or reuse one, attach only the narrowly
    scoped `GetSecretValue` / `GetParameter` permission on the specific secret or parameter ARN, and set
    the profile in the Launch Template under **Advanced details** → **IAM instance profile** before relying
    on the user-data fetch. At minimum, audit who has those `Describe*` permissions in the account.
  - **Enforce IMDSv2.** Set the Launch Template's metadata options to require a session token
    (`HttpTokens: required`, a low `HttpPutResponseHopLimit` such as `1`) so a server-side request forgery
    (SSRF) bug in a workload can't read the user data or instance role credentials from `169.254.169.254`
    without a token. IMDSv1 leaves that endpoint open to any unauthenticated in-instance request.
- **Auto Scaling Group:**
  - Testing: desired 1 / min 1 / max 1.
  - Production: desired 2 / min 2 / max 4 across at least two availability zones. Two agents give you
    a rolling-restart path during upgrades and survive a single-AZ outage.
- **Subnets:** subnets must have outbound internet access (public subnet with auto-assign IPv4, or private
  subnet with NAT). The agent dials CPLN over TLS; it does *not* need any inbound rule from the internet.
  When choosing AZs, note that not every EC2 instance type is offered in every AZ — confirm your chosen type
  is available in the AZ(s) you target, especially if you co-locate the agent with the RDS writer's AZ to
  avoid cross-AZ data-transfer charges (see [Cost](#cost)).

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

> **Simpler alternative: share the RDS SG.** Instead of managing a separate egress/ingress rule pair, you can
> attach the **RDS SG itself** to the agent instances. Each agent then carries two security groups — its own
> (egress to CPLN on `443` and the VPC DNS resolver on `53`) plus the RDS SG. If the RDS SG already has a
> self-referencing rule that allows ingress from itself on `5432`, this removes the need to maintain a
> dedicated Agent-SG → RDS-SG rule.

## Step 4 — Declare the Network Resource on the Identity

cpflow provisions a **single identity per app**, named `<app>-identity`, that is shared by every
workload in the app (see `Config#identity` and the same `{{APP_IDENTITY_LINK}}` referenced by
`templates/rails.yml`, `templates/sidekiq.yml`, and `templates/daily-task.yml`). We need to add a
`networkResources` entry to **that existing identity**, not create a new one — and not a separate
identity per workload.

> **Important: `cpln apply` is a full replace, not a merge.** Use `yaml-slim` for manifests you plan
> to re-apply; full `yaml` output can include server-managed metadata such as IDs, versions, and
> timestamps. Applying a stripped-down identity YAML
> that only contains `networkResources` will silently drop any other fields already set on the
> identity (tags, description, and any previously configured `networkResources`). Always **export
> the live identity first**, edit it in place, then re-apply. (Policy bindings themselves live on
> the Policy resource — not on the identity — so applying the identity won't touch them, but the
> verification step below still checks the policy → identity link in case anything else recreated it.)

First, find the identity name. cpflow's `Config#identity` defines this as `<app>-identity` and the
`{{APP_IDENTITY}}` template variable expands to the same — so for an app named `my-app-production` the
identity is `my-app-production-identity`. Confirm against your org (`cpln identity get` with no ref returns
all identities in the GVC; there is no `list` subcommand):

```sh
cpln identity get --gvc my-app-production --org my-org \
  | grep my-app-production-identity
```

Export it and add the `networkResources` block. Look up your VPC's DNS resolver IP (typically the VPC CIDR
base + 2, e.g. `10.0.0.2` for a `10.0.0.0/16` VPC) and your RDS cluster endpoint:

```sh
# Replace my-app-production-identity with whatever `cpln identity get` shows for your app.
cpln identity get my-app-production-identity \
  --gvc my-app-production --org my-org -o yaml-slim > identity-db.yaml
```

Edit `identity-db.yaml` and **add** the `networkResources` block — keep every other apply-safe field
exactly as exported:

> ⚠️ **Verify field casing against your org before applying.** The field names below (`FQDN`, `IPs`,
> `agentLink`, `resolverIP`) are sourced from public CPLN docs. If the live API uses different casing,
> `cpln apply` will accept the file but silently ignore the resource — workloads will hit
> `could not translate host name` with no obvious link to the identity YAML. Diff your edited file
> against the original `yaml-slim` export from `cpln identity get` to confirm.

```yaml
# identity-db.yaml (after edit — abbreviated, your file will have more fields)
kind: identity
name: my-app-production-identity   # output of `cpln identity get` for your app
description: ...                   # leave existing description alone
# … any other existing fields stay as-is …
networkResources:
  - name: db-primary           # resource identifier (TLS workloads connect via the FQDN below)
    agentLink: //agent/aws-us-east-2-prod
    FQDN: myapp-prod.cluster-xxxxx.us-east-2.rds.amazonaws.com   # ← workload connects to this endpoint
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
rm identity-db.yaml   # optional: the live identity is the source of truth; re-export anytime with `cpln identity get`
```

(Use whatever `--org` / `--gvc` flags your team uses, or rely on the org/GVC defaults set by `cpln profile`.)

Confirm the identity now has the new `networkResources` and that the policy still references it with the
`reveal` permission:

```sh
# 1. The identity itself should now list `networkResources`.
#    Use -A 15 so the full block (name, agentLink, FQDN, resolverIP, ports) is visible without re-running.
cpln identity get my-app-production-identity --gvc my-app-production --org my-org -o yaml \
  | grep -A 15 networkResources

# 2. Policies are separate resources — they reference the identity by link, not by replacing it.
#    Confirm the existing cpflow-generated policy (typically <app-prefix>-secrets-policy) has `reveal`
#    and the identity link in the same binding block. The full identity link cpflow uses is
#    /org/<org>/gvc/<app>/identity/<app>-identity (see Config#identity_link).
#    (The `cpln` CLI exposes `policy get`/`policy query` — there is no `policy list` subcommand.)
cpln policy get my-app-secrets-policy --org my-org -o yaml
```

Look for a binding shaped like this; both `reveal` and the identity link must be in the same item:

```yaml
bindings:
  - permissions:
      - reveal
    principalLinks:
      - /org/my-org/gvc/my-app-production/identity/my-app-production-identity
```

If the policy block is gone, no longer contains the identity link, or does not grant `reveal`, your workload
won't be able to read its secrets — re-bind the identity to the secrets policy directly with the CPLN CLI:

```sh
# Verify this subcommand exists in your installed cpln version first: cpln policy --help
cpln policy add-binding my-app-secrets-policy --org my-org \
  --identity /org/my-org/gvc/my-app-production/identity/my-app-production-identity \
  --permission reveal
```

This is the same call `cpflow setup-app` makes internally (see `Controlplane#bind_identity_to_policy`).
`cpflow apply-template app` does **not** recreate the binding — its `app` template only defines the
GVC, and `--add-app-identity` only inserts an identity object, not the policy binding. Adjust the
policy name if you've overridden `secrets_policy_name` in `controlplane.yml`.

> **Naming note.** The secret and policy default to `<app-prefix>-secrets` / `<app-prefix>-secrets-policy`,
> where the prefix is the matched `controlplane.yml` entry name (`Config#secrets`). That prefix can be
> **shorter than the full app name** used for the GVC and identity — e.g. an app `my-app-production` matched
> by a `my-app` entry has identity `my-app-production-identity` but secret `my-app-secrets` and policy
> `my-app-secrets-policy`. Confirm yours with `cpln secret get --gvc <app> --org <org>` if unsure.

Schema notes (per CPLN's documented `networkResources` schema):

- `name` — a short, stable identifier for the resource (`db-primary`, `db-readers`). A workload may address
  the resource by this name **or** by its `FQDN` — but a **TLS** target like RDS/Aurora must be reached by
  the `FQDN` (see Step 5), so the name serves mainly as the resource label here.
- `agentLink` — `//agent/<agent-name>` (org-scoped).
- Exactly one of `IPs` or `FQDN` is required per resource:
  - `IPs` — array of **1 to 5** IPv4 addresses. The agent routes to exactly those IPs.
  - `FQDN` — a fully qualified domain name; the agent resolves it from inside your VPC. Pair it with
    `resolverIP` (below) unless the agent can already resolve the FQDN on its own.
- `resolverIP` — **optional** IPv4 of a DNS server the agent uses to resolve the `FQDN` from inside the
  private VPC (typically the VPC's `.2` resolver, e.g. `10.0.0.2`). Not needed if the agent can already
  resolve the FQDN; when set, the agent queries this resolver for the FQDN.
- `ports` — array of **1 to 10** ports, each `0–65535`. Required.
- One identity may declare **up to 50** `networkResources`.
- For native AWS PrivateLink, an alternative `awsPrivateLink` field exists on identities (see
  [Alternatives](#alternatives--when-not-to-use-an-agent) below).

### IPs vs FQDN — which to use?

- **FQDN** (recommended for Aurora and any RDS cluster with failover): set `FQDN` to the cluster endpoint,
  and set `resolverIP` to the VPC's `.2` resolver unless the agent can already resolve the endpoint on its
  own. The agent re-resolves on connect, so there is no identity change required on failover — but plan for the full 60–120 s window (failure detection, replica
  promotion, DNS update, propagation), not just Aurora's ~30 s DNS TTL. See
  [Aurora failover](#aurora-failover) in Operations.
- **IPs** (only when you control the target's IP stability): a single-instance RDS that you don't expect to
  recycle, or a static private IP behind a network appliance. The agent will route to exactly those IPs
  — if RDS recycles the underlying instance and the IP changes, you must update the identity manually.

For most ShakaCode setups, use FQDN — and a TLS RDS/Aurora connection needs the FQDN as the `DATABASE_URL`
host anyway so the certificate matches (see Step 5). The IPs form is shown here mainly to make the schema
concrete and for the rare case where you want to pin to a specific IP.

## Step 5 — Point the workload at the resource

The workload's `DATABASE_URL` uses the **RDS/Aurora endpoint** (the `FQDN` you declared in step 4) as the
hostname, not the short resource `name` — see the TLS note below for why. CPLN still routes the endpoint
through the agent because it's declared in `networkResources`.

CPLN's `cpln://secret/<name>.<key>` syntax substitutes the **entire env var value** at workload startup — it
is not a substring interpolation. So you have three options for assembling a `DATABASE_URL` that includes a
secret password:

> **TLS requirement — use the FQDN endpoint as the host.** RDS and Aurora require TLS by default in current
> parameter groups, and their certificate is issued for the **actual cluster endpoint**. Per Control Plane,
> a TLS resource must be reached by its FQDN: connecting through the short `networkResources` name
> (`db-primary`) fails the TLS handshake unless you disable certificate validation. So use the real endpoint
> (e.g. `myapp-prod.cluster-xxxxx.us-east-2.rds.amazonaws.com`) as the `DATABASE_URL` host in every example
> below. CPLN routes it through the agent because that FQDN is declared in `networkResources`.
>
> Always include `sslmode=require` so the connection is encrypted; without it, newer clusters refuse the
> connection and older ones silently fall back to unencrypted. Because the host now matches the certificate,
> the stricter `verify-ca` / `verify-full` modes also work — add the AWS RDS CA bundle to the container image
> and reference it with `sslrootcert=/path/to/rds-ca.pem` (or `PGSSLROOTCERT`). See the
> [AWS RDS SSL/TLS docs](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html).

**Option A: store the full URL in a secret (simpler).** Recommended for production where the DB credentials
rarely change.

Add the connection string to the existing app dictionary secret created by `cpflow setup-app`
(`my-app-secrets` in these examples). **Use the CPLN UI** (Secrets → select the app secret → add keys) —
it's the safest place to enter credentials and avoids shell history, tty echo, and plaintext request bodies
entirely.

> ⚠️ **CLI form below is reference-only.** It writes credentials to your shell history, local disk, and the
> `cpln` request body in plaintext. The common "prefix with a space" trick only works when `HISTCONTROL`
> includes `ignorespace` or `ignoreboth`, which is **not** set by default on many stripped-down bastion/EC2
> shells. Prefer the UI for any real credential.

```sh
# Reference only — prefer the UI. mktemp gives an unpredictable, owner-only (mode 600) file —
# safer than a fixed path under world-readable /tmp.
secret_file=$(mktemp)
cpln secret reveal my-app-secrets --org my-org -o yaml-slim > "$secret_file"
# Edit "$secret_file" and add these keys under data, preserving existing entries:
#   url: "postgres://app:supersecret@myapp-prod.cluster-xxxxx.us-east-2.rds.amazonaws.com:5432/myapp_production?sslmode=require"
#   url_readers: "postgres://app_readonly:readsecret@myapp-prod.cluster-ro-xxxxx.us-east-2.rds.amazonaws.com:5432/myapp_production?sslmode=require"
cpln apply --file "$secret_file" --org my-org
rm -f "$secret_file"
```

> **Secret policy target.** `cpflow setup-app` creates the app secret (`my-app-secrets`) and a secrets
> policy that targets only that secret. If you instead store database values in a separate secret such as
> `my-app-database`, add `//secret/my-app-database` to the existing policy's `targetLinks` while preserving
> `//secret/my-app-secrets`; otherwise `cpln://secret/my-app-database...` references will fail at workload
> startup even if the identity has a `reveal` binding.
>
> ```sh
> cpln policy get my-app-secrets-policy --org my-org -o yaml > /tmp/my-app-secrets-policy.yml
> # Edit targetLinks to include both:
> # - //secret/my-app-secrets
> # - //secret/my-app-database
> cpln apply --file /tmp/my-app-secrets-policy.yml --org my-org
> ```
>
> See [secrets-and-env-values.md](./secrets-and-env-values.md) for the generated app secret/policy flow.

Then in your workload template:

```yaml
# In your rails.yml workload template
spec:
  containers:
    - name: rails
      env:
        - name: DATABASE_URL
          value: cpln://secret/my-app-secrets.url
        # Optional, for read replicas:
        - name: DATABASE_REPLICA_URL
          value: cpln://secret/my-app-secrets.url_readers
```

**Option B: keep the password in a secret, assemble the URL in app code.** Use this if you want the URL host
to live in plaintext config so it's easy to grep for in templates.

Add just the password to the existing app secret. Again, **prefer the CPLN UI** to enter the credential; the
CLI heredoc below is reference-only (same shell-history caveat as Option A). If you create
`my-app-database` instead of adding the password to `my-app-secrets`, update the app secrets policy
`targetLinks` as shown in Option A.

```sh
# Reference only — prefer the UI. mktemp gives an unpredictable, owner-only (mode 600) file —
# safer than a fixed path under world-readable /tmp.
secret_file=$(mktemp)
cpln secret reveal my-app-secrets --org my-org -o yaml-slim > "$secret_file"
# Edit "$secret_file" and add this key under data, preserving existing entries:
#   password: "supersecret"
cpln apply --file "$secret_file" --org my-org
rm -f "$secret_file"
```

Then set the workload env:

```yaml
env:
  - name: DATABASE_HOST
    value: myapp-prod.cluster-xxxxx.us-east-2.rds.amazonaws.com   # the networkResources[].FQDN from step 4
  - name: DATABASE_PORT
    value: "5432"
  - name: DATABASE_NAME
    value: myapp_production
  - name: DATABASE_USER
    value: app
  - name: DATABASE_PASSWORD
    value: cpln://secret/my-app-secrets.password
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

**Option C: compose the URL at the CPLN env layer with `$(VAR)` interpolation.** Use this to keep credentials
as separate secret keys *and* avoid touching `database.yml` — the workload still receives a single
`DATABASE_URL`.

While `cpln://secret/...` replaces a whole value, CPLN *also* supports `$(VAR)` references that interpolate
**other env vars** defined on the same workload. Combine the two: back each component with a secret, then
assemble `DATABASE_URL` from those env vars.

```yaml
env:
  - name: DATABASE_USER
    value: cpln://secret/my-app-secrets.DATABASE_USER
  - name: DATABASE_PASSWORD
    value: cpln://secret/my-app-secrets.DATABASE_PASSWORD
  - name: DATABASE_HOST
    value: myapp-prod.cluster-xxxxx.us-east-2.rds.amazonaws.com   # the networkResources[].FQDN from step 4
  - name: DATABASE_URL
    value: postgres://$(DATABASE_USER):$(DATABASE_PASSWORD)@$(DATABASE_HOST):5432/myapp_production?sslmode=require
```

With this form, `config/database.yml` can read `DATABASE_URL` directly
(`url: <%= ENV.fetch("DATABASE_URL") %>`) — no host/user/password plumbing required. cpflow template
variables such as `{{APP_NAME}}` also expand inside the value if you want the database name to track the app
name.

Either way:

- The host in `DATABASE_URL` is the **`FQDN`** from step 4 (e.g.
  `myapp-prod.cluster-xxxxx.us-east-2.rds.amazonaws.com`), so the TLS certificate matches. The short
  `networkResources` `name` (`db-primary` / `db-readers`) is the resource's identifier, not the connection
  host for a TLS database.
- If your workload can't reach the endpoint, diagnose with
  `cpln workload exec <workload> -- nslookup <endpoint>`. The Verification section below covers the
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
export-edit-apply loop used in Step 4: `cpln workload get <name> --gvc <gvc> -o yaml-slim > workload.yaml`,
edit `spec.identityLink`, then `cpln apply --file workload.yaml`. (`cpln workload update --help` may also
list a `--set` flag for this; verify against your installed CLI version before relying on it.)

Re-apply the workload template:

```sh
cpflow apply-template rails -a my-app-production
```

## Verification

Open an interactive shell in a one-off copy of the rails workload (with the identity, env, and image of
the live workload), then run `psql` from inside it. `cpflow run` flattens argv with `join(" ")` and does
no shell escaping (see
[`Command::Base.args_join`](https://github.com/shakacode/control-plane-flow/blob/main/lib/command/base.rb)),
so quoted multi-arg commands like
`-- bash -c 'psql "$DATABASE_URL" -c "select 1"'` won't survive round-tripping — running `psql` from
inside the interactive shell sidesteps the issue entirely.

```sh
# Step 1: open a one-off interactive shell inside the rails workload.
cpflow run -a my-app-production -w rails

# Step 2: from inside the workload shell, confirm DATABASE_URL is set and reachable.
echo "$DATABASE_URL"
psql "$DATABASE_URL" -c 'select now(), version();'
```

Expected: a current timestamp and the RDS Postgres version. Common failures:

- `could not translate host name "<rds-endpoint>" to address` — usually one of:
  - The identity isn't bound to the workload: check `spec.identityLink` on the workload, re-apply the
    template, and re-run.
  - The workload was running **before** you added `networkResources` to the identity: existing replicas
    don't pick up identity changes automatically. Recycle the workload with
    `cpflow ps:restart -a my-app-production` (or `cpflow ps:restart -a my-app-production -w <workload>`
    for one workload; lower-level equivalent:
    `cpln workload force-redeployment <workload> --gvc <gvc> --org <org>`) so new replicas start with the
    updated network resource map.
  - The agent can't resolve the endpoint: confirm the `FQDN` in `networkResources` exactly matches the RDS
    endpoint in `DATABASE_URL`, and that `resolverIP` (if set) points at a DNS server the agent can reach
    (the VPC `.2` resolver), with the agent SG allowing egress on `53`.
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
  to. The IPs you declared are routing targets, so they may now forward to the wrong instance. For Aurora
  specifically, prefer the **FQDN** form so the agent re-resolves on each connect.
- With **FQDN**: the agent re-resolves the cluster endpoint. Aurora's DNS TTL is ~30 seconds, but the full
  failover window (detection → replica promotion → DNS update → propagation to your VPC resolver) is
  typically **60–120 seconds** in practice. Size connection-pool timeouts and circuit breakers for the
  upper end of that range, not just the DNS TTL.
- Either way, the Rails connection pool will see a burst of errors during failover. The app should be
  configured to reconnect cleanly on `PG::ConnectionBad` and similar errors. Test failover behavior
  before assuming the app recovers without intervention.

### Agent sizing and upgrades

- For production, start with `t3.medium` or larger so the agent has at least 2 vCPU / 4 GiB, matching the
  CPLN recommendation from Step 2. Capacity-plan on the instance's baseline network bandwidth, not burst
  bandwidth; `t3.small` is fine for testing, but its lower baseline makes it the wrong default for production
  database connectivity. Watch agent CPU and active connection count and scale up the instance type if CPU
  stays above ~70% or connection-queue latency rises.
- CPLN occasionally publishes new agent versions. The ASG + bootstrap script combination handles upgrades
  by re-rolling instances; let it do that during low-traffic windows.

### Cost

- Two `t3.medium` instances 24/7 in `us-east-2`: roughly $60/month before data transfer; check current EC2
  pricing for your region and instance family.
- Cross-AZ data transfer between agent and RDS is **billed per-GB in each direction** even within one region,
  so steady query traffic — not just bulk loads — accumulates a charge whenever the agent and the RDS writer
  sit in different AZs. To minimize it, place an agent in the **same AZ as the RDS writer**. This trades off
  against the multi-AZ HA recommended above: for cost-sensitive setups, co-locate with the writer's AZ; for
  HA, spread across AZs and accept the cross-AZ transfer cost. Either way, keep the agent in the **same
  region** as RDS.

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
