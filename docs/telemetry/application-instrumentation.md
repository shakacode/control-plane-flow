# Application Instrumentation

Application instrumentation is the code and configuration that creates telemetry
signals. `cpflow` deploys the infrastructure around that instrumentation, but it
does not add tracing or metrics libraries to your application.

## Standard Environment Variables

Set these at the GVC level when every app workload should inherit them. Set them
on one workload container when only that workload should emit telemetry.

The snippets below are fragments, not complete templates. In a `cpflow`
template, put the `env` list under `spec.env` for GVC-level values or under the
target workload container's `spec.containers[].env` list for workload-only
values. When setting values directly in the Control Plane console or with
`cpln`, replace `{{APP_NAME}}` with the actual app name before applying it.

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://open-telemetry-collector.{{APP_NAME}}.cpln.local:4318"
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: "http/protobuf"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "deployment.environment=staging,service.namespace=example"
# This GVC-level snippet intentionally omits OTEL_SERVICE_NAME.
# Set OTEL_SERVICE_NAME per workload container, such as example-web or
# example-worker, and set inheritEnv: true on each container that should
# receive these shared values.
```

Change `deployment.environment=staging` to match the real environment. When this
value is set at the GVC level, each target workload container must set
`inheritEnv: true` to receive it. Use workload container env instead when only
one workload should receive the telemetry settings. Keep `OTEL_SERVICE_NAME`
workload-specific at the container level.

The `http://` collector endpoint is intended for a collector in the same GVC with
`same-gvc` inbound firewall isolation. Use `https://` only when a shared
telemetry endpoint terminates TLS; otherwise use the internal collector hostname
and protocol configured for that collector.

When using HTTP transport (`http/protobuf` or `http/json`), modern stable
OpenTelemetry SDKs treat `OTEL_EXPORTER_OTLP_ENDPOINT` as a base URL and append
`/v1/traces`, `/v1/metrics`, or `/v1/logs` automatically. For OTLP over gRPC,
most stable SDKs expect `http://host:port` for insecure connections and
`https://host:port` for TLS. Some older or pre-stable SDKs accepted a bare
`host:port`; check your SDK's documentation. For older or pre-stable SDKs, use
signal-specific variables such as `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` with the
full signal path when needed.

`ENABLE_OPEN_TELEMETRY` is not a standard OpenTelemetry environment variable.
Use it only if your application code explicitly reads that flag. Otherwise, use
standard SDK configuration such as `OTEL_SERVICE_NAME` and
`OTEL_EXPORTER_OTLP_ENDPOINT`, plus your framework's instrumentation setup.

## Optional StatsD TCP Variables

Use these only when your application client can send StatsD over TCP and your
collector has a matching `statsd/tcp` receiver. These environment variable names
are examples for application code that reads them; many StatsD clients require
TCP transport to be configured explicitly in code.

```yaml
env:
  - name: STATSD_HOST
    value: "open-telemetry-collector.{{APP_NAME}}.cpln.local"
  - name: STATSD_PORT
    value: "9127"
  - name: STATSD_PROTOCOL
    value: "tcp"
```

`9127` is project-specific. The StatsD protocol default is `8125/UDP`; use the
port your collector's `statsd/tcp` receiver is configured to bind.

When applying with `cpln` directly, replace `{{APP_NAME}}` with the actual app
name.

## Generic Ruby Example

This example uses deliberately generic metric names. Keep labels low-cardinality.
Initialize your client with TCP transport before emitting metrics. The exact
constructor name varies by library, but do not rely on the client's default
transport when the collector listens on `statsd/tcp`.

```ruby
statsd = MyStatsDClient.new(
  host: ENV.fetch("STATSD_HOST"),
  port: Integer(ENV.fetch("STATSD_PORT", "9127")),
  protocol: ENV.fetch("STATSD_PROTOCOL", "tcp")
)

statsd.increment(
  "example.tasks.completed",
  tags: ["task_type:background", "status:success"]
)

statsd.timing(
  "example.jobs.duration_ms",
  elapsed_ms,
  tags: ["job_type:scheduled"]
)
```

Avoid tags such as `user_id`, `request_id`, raw URLs, or free-form error
messages. They create high-cardinality metrics and can leak sensitive data.

## Generic Node.js Example

```javascript
const statsdHost = process.env.STATSD_HOST;
if (!statsdHost) {
  throw new Error("STATSD_HOST is not set");
}

const statsd = createStatsDClient({
  host: statsdHost,
  port: (() => {
    const port = parseInt(process.env.STATSD_PORT || "9127", 10);
    if (!Number.isFinite(port)) {
      throw new Error(`Invalid STATSD_PORT: ${process.env.STATSD_PORT}`);
    }
    return port;
  })(),
  protocol: process.env.STATSD_PROTOCOL || "tcp",
});

statsd.increment("example.requests.completed", 1, {
  route: "health_check",
  status: "success",
});

statsd.histogram("example.worker.duration_ms", elapsedMs, {
  worker: "default",
});
```

## Service Names

Use names that identify the workload, not a real organization, account, or user.

Good:

- `example-web`
- `example-worker`
- `example-scheduler`

Avoid:

- real organization names
- account names
- user identifiers
- business-specific nouns copied from one product into reusable docs

## Logs

Keep logs structured, redacted, and useful without a collector. If your
application sends OTLP logs, use the same collector endpoint as traces and
metrics. If it logs to stdout/stderr, use `cpflow logs` for live tailing and the
platform log backend for historical queries.
