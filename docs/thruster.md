# Thruster HTTP/2 Proxy on Control Plane

[Thruster](https://github.com/basecamp/thruster) is Basecamp's zero-config HTTP/2 proxy for
Ruby web applications. It provides HTTP/2 support, asset caching, compression, and early
hints. Running it on Control Plane requires settings that differ from a standalone (e.g.,
VPS) deployment, and getting them wrong produces a confusing `502 Bad Gateway` with a
"protocol error" message.

This page documents the configuration that works.

## TL;DR

- Workload port: `protocol: http` (not `http2`).
- Dockerfile `CMD` runs Thruster: `CMD ["bundle", "exec", "thrust", "bin/rails", "server"]`.
- End users still get HTTP/2; Control Plane's load balancer handles TLS termination.

## Why `protocol: http` and not `http2`

### Standalone Thruster (e.g., VPS)

```
User → HTTPS/HTTP2 → Thruster → HTTP/1.1 → Rails
      (Thruster handles TLS + HTTP/2)
```

### Control Plane + Thruster

```
User → HTTPS/HTTP2 → Control Plane LB → HTTP/1.1 → Thruster → HTTP/1.1 → Rails
                      (LB handles TLS)    (protocol: http)  (caching, compression)
```

In the diagram above, `protocol: http` is the workload port setting that governs the
LB→Thruster hop; `caching, compression` describes what Thruster contributes in this
path.

On Control Plane, the load balancer terminates TLS and speaks HTTP/2 to the browser —
so Thruster never sees TLS or HTTP/2 on its incoming side. This is the opposite of a
standalone (VPS) deployment, where Thruster itself handles TLS and HTTP/2. Setting
`protocol: http2` on the workload port tells the load balancer to expect HTTP/2 from
the container, which Thruster does not emit on that hop, and protocol negotiation fails
with `502 Bad Gateway`.

Even with `protocol: http`, end users still get:

- HTTP/2 to the browser (from the Control Plane load balancer)
- HTTP/2 multiplexing (from the Control Plane load balancer)
- Asset caching and compression (from Thruster)
- Efficient static file serving (from Thruster)
- Early Hints (103) from Thruster (reaches the browser only if the load balancer forwards 103 responses)

## Workload template

In `.controlplane/templates/rails.yml`:

```yaml
ports:
  - number: 3000
    protocol: http  # Required when fronting Rails with Thruster. Do not use http2.
```

## Dockerfile

The container's `CMD` must launch Thruster. On Control Plane/Kubernetes the Dockerfile
`CMD` determines container startup — the `Procfile` is not used (unlike Heroku).

```dockerfile
# .controlplane/Dockerfile
CMD ["bundle", "exec", "thrust", "bin/rails", "server"]
```

## Troubleshooting

### `502 Bad Gateway` with "protocol error"

The workload port is set to `protocol: http2`. Change it to `protocol: http` in
`rails.yml`, then push the workload spec.

`cpflow apply-template` rewrites the workload from the template. If you have tuned
CPU, memory, autoscaling, firewall, or other workload fields directly in the
Control Plane UI (or via `cpln`) without mirroring those changes back into
`rails.yml`, those edits will be reset. Either reconcile `rails.yml` with the live
spec first, or change the port field in place:

```sh
# Option A — apply the full template (resets any drift between rails.yml and the live spec):
cpflow apply-template rails -a <app>

# Option B — edit only the port protocol in place (preserves UI-tuned fields):
cpln workload edit <workload> --gvc <gvc> --org <org>
# change spec.containers[].ports[].protocol from http2 to http
```

Inspect the current spec before choosing if you're unsure what would change:

```sh
cpln workload get <workload> --gvc <gvc> --org <org> -o yaml
```

Note: `cpflow deploy-image` alone is not sufficient — it only updates the container
image reference and does not modify the workload's port configuration. Run it
*after* the protocol change has been applied if you also want to ship a new image.

The remaining troubleshooting commands use the raw Control Plane CLI (`cpln`) rather
than `cpflow`; see
[the Control Plane CLI quickstart](https://shakadocs.controlplane.com/quickstart/quick-start-3-cli#getting-started-with-the-cli)
if you don't already have it installed.

### Verify Thruster is the process running as PID 1

`/proc/1/cmdline` stores arguments NUL-separated with no trailing newline, so pipe it
through `tr` to make the output readable:

```sh
cpln workload exec <workload> --gvc <gvc> --org <org> --location <location> \
  -- sh -c "tr '\0' ' ' < /proc/1/cmdline && echo"
```

You should see `thrust` in the output. If you see `rails` or `puma` directly, the
Dockerfile `CMD` is not invoking Thruster.

### Test HTTP connectivity through Thruster

This hits Thruster on port 3000 — not Rails directly. A `200 OK` confirms the
Thruster → Rails path within the container is healthy.

```sh
cpln workload exec <workload> --gvc <gvc> --org <org> --location <location> \
  -- curl -s localhost:3000
```

### Inspect the workload port configuration

```sh
cpln workload get <workload> --gvc <gvc> --org <org> -o json | jq '.spec.containers[].ports'
```

## Reference implementation

A working setup lives in the
[react-webpack-rails-tutorial](https://github.com/shakacode/react-webpack-rails-tutorial)
repository — see
[`.controlplane/templates/rails.yml`](https://github.com/shakacode/react-webpack-rails-tutorial/blob/master/.controlplane/templates/rails.yml)
on the `master` branch.

## Further reading

- [Thruster on GitHub](https://github.com/basecamp/thruster)
- [DHH on Rails 8 with Thruster](https://world.hey.com/dhh/rails-8-with-thruster-by-default-c953f5e3)
