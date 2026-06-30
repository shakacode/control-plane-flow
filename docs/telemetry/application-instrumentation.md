# Application Instrumentation

Application instrumentation is the code and configuration that creates telemetry
signals. `cpflow` deploys the infrastructure around that instrumentation, but it
does not add tracing or metrics libraries to your application.

## Standard Environment Variables

Set these at the GVC level when every app workload should inherit them. Set them
on one workload container when only that workload should emit telemetry.

```yaml
env:
  - name: OTEL_SERVICE_NAME
    value: "example-web"
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://open-telemetry-collector.{{APP_NAME}}.cpln.local:4318"
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: "http/protobuf"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "deployment.environment=staging,service.namespace=example"
```

`ENABLE_OPEN_TELEMETRY` is not a standard OpenTelemetry environment variable.
Use it only if your application code explicitly reads that flag. Otherwise, use
standard SDK configuration such as `OTEL_SERVICE_NAME` and
`OTEL_EXPORTER_OTLP_ENDPOINT`, plus your framework's instrumentation setup.

## Optional StatsD TCP Variables

Use these only when your application client can send StatsD over TCP and your
collector has a matching `statsd/tcp` receiver.

```yaml
env:
  - name: STATSD_HOST
    value: "open-telemetry-collector.{{APP_NAME}}.cpln.local"
  - name: STATSD_PORT
    value: "9127"
  - name: STATSD_PROTOCOL
    value: "tcp"
```

## Generic Ruby Example

This example uses deliberately generic metric names. Keep labels low-cardinality.

```ruby
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
