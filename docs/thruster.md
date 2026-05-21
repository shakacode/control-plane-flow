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
- End users still get HTTP/2; Control Plane's load balancer terminates it.

## Why `protocol: http` and not `http2`

### Standalone Thruster (e.g., VPS)

```
User → HTTPS/HTTP2 → Thruster → HTTP/1.1 → Rails
      (Thruster handles TLS + HTTP/2)
```

### Control Plane + Thruster

```
User → HTTPS/HTTP2 → Control Plane LB → HTTP/1.1 → Thruster → HTTP/1.1 → Rails
                      (LB handles TLS)    (protocol: http)  (HTTP/2 features)
```

Thruster speaks HTTP/2 on the *frontend* (the TLS-terminated connection from the browser)
and talks to upstream services over HTTP/1.1. On Control Plane the load balancer
terminates TLS, so it is the load balancer — not Thruster — that talks HTTP/2 to the
browser. Setting `protocol: http2` on the workload port tells the load balancer to expect
HTTP/2 from the container, which Thruster does not provide on that hop, and protocol
negotiation fails with `502 Bad Gateway`.

Even with `protocol: http`, end users still get:

- HTTP/2 to the browser (via the Control Plane load balancer)
- Asset caching and compression
- Efficient static file serving
- Early hints support
- HTTP/2 multiplexing

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

The workload port is set to `protocol: http2`. Change it to `protocol: http` and redeploy.

### Verify Thruster is the process running as PID 1

```sh
cpln workload exec <workload> --gvc <gvc> --org <org> --location <location> \
  -- cat /proc/1/cmdline
```

You should see `thrust` in the output. If you see `rails` or `puma` directly, the
Dockerfile `CMD` is not invoking Thruster.

### Test internal connectivity to Rails

```sh
cpln workload exec <workload> --gvc <gvc> --org <org> --location <location> \
  -- curl -s localhost:3000
```

### Inspect the workload port configuration

```sh
cpln workload get <workload> --gvc <gvc> --org <org> -o json | grep -A 3 "ports"
```

## Reference implementation

A working setup lives in the
[react-webpack-rails-tutorial](https://github.com/shakacode/react-webpack-rails-tutorial)
repository — see
[PR #687](https://github.com/shakacode/react-webpack-rails-tutorial/pull/687).

## Further reading

- Thruster: https://github.com/basecamp/thruster
- DHH on Rails 8 with Thruster: https://world.hey.com/dhh/rails-8-with-thruster-by-default-c953f5e3
