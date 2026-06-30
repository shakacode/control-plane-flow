# Collector Workload

The OpenTelemetry Collector is a telemetry router. It receives data from
application workloads, optionally processes or samples it, and exports it to one
or more backends.

The two files that must agree are:

1. The Control Plane workload template, which exposes ports.
2. The collector `config.yaml`, which binds receivers and exporters to those
   same ports.

If these files disagree, telemetry can fail silently.

## Control Plane Workload Template

Add a template such as
`.controlplane/templates/open-telemetry-collector.yml`.

```yaml
kind: workload
name: open-telemetry-collector
spec:
  type: standard
  containers:
    - name: open-telemetry-collector
      image: "registry.example.com/example/open-telemetry-collector:0.155.0"
      args:
        - "--config=/etc/otelcol-contrib/config.yaml"
      # Uncomment when config.yaml references ${env:TELEMETRY_BACKEND_TOKEN}.
      # env:
      #   - name: TELEMETRY_BACKEND_TOKEN
      #     value: cpln://secret/{{APP_NAME}}-telemetry-backend.TELEMETRY_BACKEND_TOKEN
      cpu: 100m
      memory: 256Mi
      ports:
        # OTLP over HTTP from application SDKs.
        - number: 4318
          protocol: http
        # StatsD over TCP, not UDP. Delete this port unless your collector
        # config enables statsd/tcp and app clients set TCP transport.
        # 9127 is project-specific; StatsD defaults to 8125/UDP.
        # When deleting it, also remove receivers.statsd/tcp and statsd/tcp
        # from service.pipelines.metrics.receivers in config.yaml.
        - number: 9127
          protocol: tcp
        # Prometheus-formatted metrics exposed by the collector.
        - number: 9292
          protocol: http
  defaultOptions:
    autoscaling:
      metric: disabled
      minScale: 1
      maxScale: 1
    capacityAI: false
  firewallConfig:
    internal:
      inboundAllowType: same-gvc
    external:
      # Prefer a narrow allowlist for production. Use the hostnames or CIDRs
      # required by your telemetry backend.
      outboundAllowHostname:
        - telemetry-backend.example.com
  # Use a collector-specific identity when the collector reads telemetry
  # backend secrets that app workloads should not reveal.
  identityLink: "//identity/{{APP_NAME}}-otel-collector-identity"
```

Use `outboundAllowCIDR` instead of `outboundAllowHostname` when your backend
requires IP ranges. Avoid leaving collector egress open to `0.0.0.0/0` in
production unless your security model explicitly accepts that risk.

Create the collector identity and a secret policy in a separate
`open-telemetry-collector-secrets` template before applying the workload
template if the collector reads backend tokens from Control Plane secrets:

```yaml
kind: identity
name: "{{APP_NAME}}-otel-collector-identity"
description: "{{APP_NAME}}-otel-collector-identity"

---
kind: policy
name: "{{APP_NAME}}-otel-collector-secrets"
description: "{{APP_NAME}}-otel-collector-secrets"
bindings:
  - permissions:
      - reveal
    principalLinks:
      - "//gvc/{{APP_NAME}}/identity/{{APP_NAME}}-otel-collector-identity"
targetKind: secret
targetLinks:
  - "//secret/{{APP_NAME}}-telemetry-backend"
```

Create the `{{APP_NAME}}-telemetry-backend` dictionary secret with a
`TELEMETRY_BACKEND_TOKEN` key, or replace that name consistently before
applying the templates. Keep this policy scoped to only the backend secret the
collector needs.

`cpflow apply-template` replaces `{{APP_NAME}}` with the actual app name. When
applying the YAML directly with `cpln`, replace `{{APP_NAME}}` manually before
running `cpln apply`.

Keep the collector image pinned to a tested release and update it as part of
normal dependency maintenance. Do not rely on a floating `latest` tag for
production workloads.

## Delivering Collector Config

The official collector image does not include your application-specific
`config.yaml`. A simple Control Plane pattern is to build a small collector image
that starts from the pinned upstream image and copies the config into the path
used by the workload command.

```dockerfile
FROM otel/opentelemetry-collector-contrib:0.155.0

COPY config.yaml /etc/otelcol-contrib/config.yaml
```

Build this image, publish it to your registry, and set the workload template
`image:` field to that published image. The upstream image is only the base image
for this Dockerfile because it does not contain your `config.yaml`.

Baking the config into the image keeps collector startup deterministic. If your
team already manages runtime files through Control Plane, you can instead mount a
secret-backed file with a `cpln://secret/...` URI and `path:` entry, following
the same pattern used by other file-delivery templates.

## Matching Collector Config

Mount or bake the collector config at the path passed to `--config`. The contrib
image convention is `/etc/otelcol-contrib/config.yaml`; use a different path only
when your image or command is built for it.

The collector config must bind every exposed port. This minimal config receives
OTLP over HTTP, optionally receives StatsD over TCP, and exposes metrics for
Prometheus scraping.

```yaml
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318

  statsd/tcp:
    endpoint: 0.0.0.0:9127
    transport: tcp
    aggregation_interval: 60s

processors:
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80
    spike_limit_percentage: 20

  batch: {}

exporters:
  prometheus:
    endpoint: 0.0.0.0:9292

  # Replace this placeholder with your real trace/log backend.
  otlphttp/backend:
    # otlphttp treats this as a base endpoint and appends /v1/traces,
    # /v1/metrics, or /v1/logs for each signal.
    endpoint: "https://telemetry-backend.example.com"
    # headers:
    #   Authorization: "Bearer ${env:TELEMETRY_BACKEND_TOKEN}"

  # Optional validation-only exporter. Do not leave debug in production
  # pipelines because it writes telemetry payloads to collector logs.
  # debug:
  #   verbosity: basic

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlphttp/backend]

    metrics:
      receivers: [otlp, statsd/tcp]
      processors: [memory_limiter, batch]
      exporters: [prometheus, otlphttp/backend]

    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlphttp/backend]
```

Before applying the config, replace `telemetry-backend.example.com` with your
real backend endpoint and headers. Keep `memory_limiter` before `batch`, and
keep the Prometheus exporter only when your platform or backend scrapes collector
metrics from port `9292`. For push-only metrics backends, remove `prometheus`
from the metrics pipeline and keep `otlphttp/backend`. If your application only
sends OTLP metrics and does not use StatsD, also remove the `statsd/tcp`
receiver block and `statsd/tcp` from the `metrics.receivers` list. See
[StatsD and UDP](#statsd-and-udp) for the full three-piece removal.

Store backend tokens such as `TELEMETRY_BACKEND_TOKEN` in Control Plane secrets
and bind them only to the collector workload identity shown in the template
above. Create the collector identity and a policy that grants `reveal` on only
the telemetry backend secret before applying the collector workload. When the
collector config references `${env:TELEMETRY_BACKEND_TOKEN}`, also add the
matching `env` entry to the collector workload so Control Plane injects the
secret value at startup. Use the app identity placeholder only when the collector
does not need secrets that are isolated from app workloads. See
[Secrets and ENV Values](../secrets-and-env-values.md) for the recommended
pattern.

The Prometheus exporter exposes an unauthenticated scrape endpoint. With
`same-gvc` firewall isolation, any workload in the same GVC that can reach port
`9292` can read exported metrics. Widen collector inbound access only when that
is acceptable.

Port `9292` is an example scrape port. Configure your scraper to match the port
you expose in the workload template and bind in the collector config.

## StatsD and UDP

The upstream OpenTelemetry StatsD receiver defaults to UDP on port `8125`.
Control Plane workload templates in this repository currently use `http` and
`tcp` ports, not `udp`. Do not document or deploy UDP StatsD on Control Plane
unless you have verified that the platform supports the required UDP forwarding
path for your workload.

Safer defaults:

1. Prefer OTLP metrics over HTTP on `4318`.
2. Use StatsD over TCP only when your app client and collector build support it.
3. Treat UDP StatsD as an environment-specific advanced option.

If you remove StatsD, remove all three pieces together: the workload port, the
`statsd/tcp` receiver block, and `statsd/tcp` from the metrics pipeline
receivers.

## `controlplane.yml`

Include the collector in setup and informational commands:

```yaml
aliases:
  common: &common
    setup_app_templates:
      - app
      - worker
      - open-telemetry-collector-secrets
      - open-telemetry-collector

    app_workloads:
      - app
      - worker

    additional_workloads:
      - open-telemetry-collector

apps:
  example:
    <<: *common
```

Use `open-telemetry-collector-secrets` for the identity and policy YAML shown
above. List it before `open-telemetry-collector` so `cpflow setup-app` creates
the collector identity and secret reveal policy before applying the workload
that references `identityLink`.

Keep `app_workloads` limited to real application workloads such as `app` and
`worker`. Put the collector under `additional_workloads` so informational
commands show it without treating it as an app process.

For an existing app, apply the identity and policy template before applying the
collector workload:

```sh
cpflow apply-template open-telemetry-collector-secrets -a $APP_NAME
cpflow apply-template open-telemetry-collector -a $APP_NAME
```

For a brand-new app, `cpflow setup-app` applies both collector templates with
the other entries listed in `setup_app_templates`, in the order shown above.

## Port Agreement Checklist

| Purpose | Workload port | Collector config |
| --- | --- | --- |
| OTLP HTTP | `4318`, `protocol: http` | `receivers.otlp.protocols.http.endpoint: 0.0.0.0:4318` |
| StatsD TCP | `9127`, `protocol: tcp` | `receivers.statsd/tcp.endpoint: 0.0.0.0:9127` and `transport: tcp` |
| Prometheus output | `9292`, `protocol: http` | `exporters.prometheus.endpoint: 0.0.0.0:9292` |

Remove any port that is not enabled in the collector config.
