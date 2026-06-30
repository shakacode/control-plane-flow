# Telemetry

This guide shows how to run application telemetry on Control Plane with `cpflow`.
`cpflow` does not instrument your application code. Instead, it helps you deploy
the Control Plane workloads and environment variables that instrumented apps use
to send traces, metrics, and logs.

The recommended shape is:

```text
Application workloads
  -> OpenTelemetry Collector workload in the same GVC
  -> tracing, metrics, and logging backends
```

## What `cpflow` Provides

`cpflow apply-template` can already apply ordinary Control Plane workload
templates from `.controlplane/templates`. That means telemetry can be added with
project templates and app environment values; no custom `cpflow` command is
required.

Use `cpflow` for:

1. Deploying an OpenTelemetry Collector workload template.
2. Applying app or workload environment variables that point to the collector.
3. Reusing the same setup for review, staging, and production apps.
4. Tailing collector logs with `cpflow logs`.

Application code is still responsible for:

1. Installing OpenTelemetry, StatsD, Prometheus, or framework-specific
   instrumentation libraries.
2. Setting service names and resource attributes.
3. Creating custom spans or metrics.
4. Filtering sensitive data before it leaves the process.

## Collector Workload

Add a collector workload template such as
`.controlplane/templates/open-telemetry-collector.yml`.

The exact image and config path depend on how your team packages collector
configuration. For production, pin the collector image version and make sure the
image or mounted configuration contains your full collector config.

```yaml
kind: workload
name: open-telemetry-collector
spec:
  type: standard
  containers:
    - name: open-telemetry-collector
      image: "otel/opentelemetry-collector-contrib:0.103.0"
      args:
        - "--config=/etc/otelcol/config.yaml"
      cpu: 100m
      memory: 256Mi
      ports:
        # OTLP over HTTP from app SDKs
        - number: 4318
          protocol: http
        # StatsD direct metrics
        - number: 9126
          protocol: udp
        # StatsD TCP fallback
        - number: 9127
          protocol: tcp
        # Prometheus-formatted metrics exposed by the collector
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
      outboundAllowCIDR:
        - 0.0.0.0/0
```

Then include the collector in app setup:

```yaml
aliases:
  common: &common
    setup_app_templates:
      - app
      - open-telemetry-collector
      - rails
      - sidekiq

    app_workloads:
      - rails
      - sidekiq

    additional_workloads:
      - open-telemetry-collector
```

Apply it with:

```sh
cpflow apply-template open-telemetry-collector -a $APP_NAME
```

Or let `cpflow setup-app` apply it with the rest of the configured templates.

## Application Environment

Set application telemetry env vars at the GVC level when every app workload
should inherit them, or at the workload container level when only one workload
should emit telemetry.

For OTLP over HTTP:

```yaml
env:
  - name: ENABLE_OPEN_TELEMETRY
    value: "true"
  - name: OTEL_SERVICE_NAME
    value: "my-app-rails"
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://open-telemetry-collector.{{APP_NAME}}.cpln.local:4318"
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: "http/protobuf"
```

For StatsD direct metrics:

```yaml
env:
  - name: STATSD_HOST
    value: "open-telemetry-collector.{{APP_NAME}}.cpln.local"
  - name: STATSD_PORT
    value: "9126"
```

Prefer direct metrics when application code can emit them. Direct metrics avoid
collector-side regex parsing and are usually cheaper and easier to reason about
than deriving metrics from logs.

## Signals

### Traces

Use OpenTelemetry SDKs or framework auto-instrumentation in your application.
Send traces to the collector's OTLP HTTP endpoint on port `4318`.

Good default attributes include:

- `service.name`
- `deployment.environment`
- `service.version` or commit SHA
- low-cardinality workload names

Avoid high-cardinality attributes such as request IDs, user IDs, raw URLs, and
unbounded error messages.

### Metrics

For application-defined metrics, emit StatsD or OTLP metrics directly from the
application. Common examples include:

- request counters
- queue depth gauges
- job duration histograms
- integration failure counters

The collector can expose Prometheus-formatted metrics on port `9292`. Configure
your metrics backend to scrape that endpoint according to your Control Plane and
Grafana setup.

### Logs

Keep application logs useful on their own: structured, redacted, and emitted to
stdout/stderr. Use log-derived metrics only for temporary prototyping or legacy
paths where direct instrumentation is not practical, because regex processing in
the collector can become expensive.

## Review Apps

Telemetry for review apps should be isolated from production telemetry.

Recommended defaults:

1. Use a collector inside each review app GVC or a staging-only collector.
2. Keep collector inbound access internal with `same-gvc` unless there is a
   specific reason to expose it.
3. Do not give review apps production telemetry tokens.
4. Keep sampling rates and retention lower for noisy review environments.
5. Avoid sending request bodies, secrets, credentials, or personally identifiable
   information in spans, labels, or logs.

## Troubleshooting

Check that the collector workload exists:

```sh
cpflow ps -a $APP_NAME -w open-telemetry-collector
```

Tail collector logs:

```sh
cpflow logs -a $APP_NAME -w open-telemetry-collector
```

Check application logs for exporter errors:

```sh
cpflow logs -a $APP_NAME -w rails
```

If telemetry is missing:

1. Confirm the app workload can resolve
   `open-telemetry-collector.$APP_NAME.cpln.local`.
2. Confirm the collector listens on the expected ports.
3. Confirm app env vars are set on the GVC or workload container.
4. Confirm the application instrumentation library is enabled.
5. Confirm the collector config exports to the expected backend.

## Future `cpflow` Enhancements

The docs-only setup above works with existing `cpflow` behavior. A small future
code enhancement could make telemetry safer by adding a deploy-time required ENV
check. Apps could declare names such as `OTEL_SERVICE_NAME`,
`OTEL_EXPORTER_OTLP_ENDPOINT`, `STATSD_HOST`, and `STATSD_PORT` in
`controlplane.yml`, and `cpflow deploy-image` or `cpflow doctor` could fail
before deployment when those values are missing from the GVC or app workload.

Another optional enhancement would be an opt-in generated collector template.
That should stay opt-in because teams package collector config and exporters in
different ways.
