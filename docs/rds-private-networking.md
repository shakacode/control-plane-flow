# Connecting Control Plane workloads to a private AWS RDS/Aurora database

Control Plane (CPLN) does not offer a managed Postgres service. For production Postgres on AWS, the typical setup
is **Amazon RDS** (or **Aurora**) in a **private VPC subnet**, reached from CPLN workloads over a private network
path — not the public internet.

This guide covers the recommended setup: **CPLN Cloud Wormhole via an Agent**.

> **Sourcing note.** Field names, schema, and limits in this guide are sourced from the public Control Plane
> documentation at <https://shakadocs.controlplane.com> as of the date this doc was written. The YAML and CLI snippets
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
- Identity + Agent are at the **org** level. Network resources are declared on the Identity (which is per-GVC).

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
> The bootstrap token is then retrieved separately via the UI or `cpln agent ...` (verify with
> `cpln agent --help`).

## Step 2 — Launch the Agent on AWS

Recommended baseline:

- **AMI:** Ubuntu Server 24.04 LTS.
- **Instance type:** `t3.small` for testing; `t3.medium` or larger for production (CPLN recommends a minimum of
  2 vCPU / 4 GiB).
- **Launch Template:** set the user data to the bootstrap script from step 1.
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

Two security groups, one rule on each:

- **Agent SG** (attached to the ASG instances): egress to the RDS SG on port `5432` (or `3306` for MySQL).
- **RDS SG** (attached to the DB cluster): ingress from the Agent SG on port `5432`.

```text
Agent SG egress    ──►  RDS SG  port 5432
RDS SG  ingress    ◄──  Agent SG port 5432
```

Reference the agent SG by ID, not by CIDR. That way, the rule stays correct as ASG instances are recycled.

## Step 4 — Declare the Network Resource on the Identity

cpflow already provisions one Identity per workload (used for binding secrets — see
`{{APP_IDENTITY_LINK}}` in `templates/rails.yml`). Extend that identity with a `networkResources` entry that
points at your RDS endpoint through the agent.

cpflow stores identities per GVC (see the existing template at
`spec/dummy/.controlplane/templates/app.yml`), so the GVC scoping comes from the apply command, not from a
top-level YAML field. Look up your VPC's DNS resolver IP (typically the VPC CIDR base + 2, e.g. `10.0.0.2`
for a `10.0.0.0/16` VPC) and your RDS cluster endpoint, then write the identity YAML:

```yaml
# identity-db.yaml
kind: identity
name: rails              # match the existing cpflow identity name for the workload (typically {{APP_IDENTITY}})
description: Adds wormhole network resources for private RDS access.
networkResources:
  - name: db-primary     # ← workload connects to this hostname
    agentLink: //agent/aws-us-east-2-prod
    FQDN: myapp-prod.cluster-xxxxx.us-east-2.rds.amazonaws.com
    resolverIP: 10.0.0.2   # your VPC's .2 resolver, reachable from the agent
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

Apply it against the right GVC:

```sh
cpln apply --file identity-db.yaml --gvc my-app-production --org my-org
```

(Use whatever `--org` / `--gvc` flags your team uses, or rely on the org/GVC defaults set by `cpln profile`.)

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
  [Alternatives](#alternatives-when-not-to-use-an-agent) below).

### IPs vs FQDN — which to use?

- **FQDN** (recommended for Aurora and any RDS cluster with failover): set `FQDN` to the cluster endpoint
  and `resolverIP` to the VPC's `.2` resolver. The agent re-resolves on connect, so Aurora's DNS-based
  writer failover propagates within ~30 seconds without any identity changes.
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

**Option A: store the full URL in a secret (simpler).** Recommended for production where the DB credentials
rarely change.

Create a dictionary secret holding the entire connection string:

```sh
cpln apply --file - <<'YAML'
kind: secret
name: my-app-database
type: dictionary
data:
  url: "postgres://app:supersecret@db-primary:5432/myapp_production"
  url_readers: "postgres://app_readonly:readsecret@db-readers:5432/myapp_production"
YAML
```

Make sure the existing app policy grants `reveal` on this new secret — see `docs/secrets-and-env-values.md`.

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
```

Either way:

- `db-primary` / `db-readers` are the `networkResources[].name` values from step 4.
- If your workload runtime doesn't resolve the bare `db-primary` hostname, try the GVC-suffixed form
  `db-primary.<gvc-name>.cpln.local` — that's the pattern cpflow uses for workload-to-workload DNS, and
  documented network resources may follow the same convention. Confirm with `cpln workload exec ... -- nslookup db-primary`.

Re-apply the workload template:

```sh
cpflow apply-template rails -a my-app-production
```

## Verification

From a one-off workload in the same GVC, confirm connectivity:

```sh
# Run psql inside the rails workload, using the live identity binding.
cpflow run -a my-app-production -- psql "$DATABASE_URL" -c 'select now(), version();'
```

Expected: a current timestamp and the RDS Postgres version. If you instead see
`could not translate host name "db-primary" to address`, the identity is not bound to the workload (check
`spec.identityLink`). If you see `connection refused` or timeouts, the agent → RDS path is wrong — check
security groups and the agent heartbeat.

## Operations

### High availability

- Run **at least 2 agents** in the ASG in production. Agent upgrades are rolling, and a single agent is a
  single point of failure for *all* private connectivity from the GVC.
- Spread the ASG across at least 2 availability zones.

### Aurora failover

- With **IPs** in `networkResources`: failover swaps which underlying instance the writer endpoint resolves
  to. The IPs you've allowlisted may now point at the wrong instance. For Aurora specifically, prefer the
  **FQDN** form so the agent re-resolves on each connect.
- With **FQDN**: the agent re-resolves the cluster endpoint. Writer failover typically propagates within
  ~30 seconds via Aurora's DNS update.
- Either way, the Rails connection pool will see a burst of errors during failover. The app should be
  configured to reconnect cleanly on `PG::ConnectionBad` and similar errors. Test failover behavior
  before assuming the app recovers without intervention.

### Agent sizing and upgrades

- Network throughput is the typical bottleneck — `t3.small` saturates around a few hundred Mbps. Scale up
  the instance type before scaling out if you push significant traffic.
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
