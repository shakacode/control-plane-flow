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
      image: "otel/opentelemetry-collector-contrib:0.103.0"
      args:
        - "--config=/etc/otelcol-contrib/config.yaml"
      cpu: 100m
      memory: 256Mi
      ports:
        # OTLP over HTTP from application SDKs.
        - number: 4318
          protocol: http
        # Optional StatsD over TCP. Use only if your collector config enables it.
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
```

Use `outboundAllowCIDR` instead of `outboundAllowHostname` when your backend
requires IP ranges. Avoid leaving collector egress open to `0.0.0.0/0` in
production unless your security model explicitly accepts that risk.

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
  batch: {}

exporters:
  prometheus:
    endpoint: 0.0.0.0:9292

  # Replace debug with your real trace/log exporters before production use.
  # Debug can print telemetry payloads, so use it only while validating setup.
  debug:
    verbosity: basic

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug]

    metrics:
      receivers: [otlp, statsd/tcp]
      processors: [batch]
      exporters: [prometheus]

    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug]
```

For production, replace `debug` with the exporter for your tracing or logging
backend. Keep the Prometheus exporter only when your platform or backend scrapes
collector metrics from port `9292`.

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

## `controlplane.yml`

Include the collector in setup and informational commands:

```yaml
aliases:
  common: &common
    setup_app_templates:
      - app
      - worker
      - open-telemetry-collector

    app_workloads:
      - app
      - worker

    additional_workloads:
      - open-telemetry-collector
```

Apply the collector template directly:

```sh
cpflow apply-template open-telemetry-collector -a $APP_NAME
```

Or let `cpflow setup-app` apply it with the other templates listed in
`setup_app_templates`.

## Port Agreement Checklist

| Purpose | Workload port | Collector config |
| --- | --- | --- |
| OTLP HTTP | `4318`, `protocol: http` | `receivers.otlp.protocols.http.endpoint: 0.0.0.0:4318` |
| StatsD TCP | `9127`, `protocol: tcp` | `receivers.statsd/tcp.endpoint: 0.0.0.0:9127` and `transport: tcp` |
| Prometheus output | `9292`, `protocol: http` | `exporters.prometheus.endpoint: 0.0.0.0:9292` |

Remove any port that is not enabled in the collector config.
