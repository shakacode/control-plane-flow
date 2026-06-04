# Grafana and OpenTelemetry on Control Plane

Control Plane already exposes useful platform metrics in Grafana: workload CPU,
memory, restarts, request rate, and similar infrastructure signals. For Rails
applications, that is a strong starting point, but it does not explain enough
about application behavior.

OpenTelemetry fills the app-level gaps:

- request and job latency
- request and job errors
- database and Redis span latency
- external HTTP API latency
- trace-to-log correlation
- custom metrics generated from common span or log patterns

The fastest dashboards usually come from generated metrics, not raw trace or log
queries. A collector can receive traces/logs, normalize them, generate focused
Prometheus metrics, and expose those metrics for Control Plane Grafana to scrape.

## High-Level Architecture

```text
Rails workloads
  -> OTLP HTTP traces/logs
  -> internal OpenTelemetry collector workload
  -> span/log processors
  -> generated Prometheus metrics
  -> Control Plane metrics scrape
  -> Grafana dashboards and alerts
```

The collector should be internal-only. Application workloads send telemetry to
the collector over the GVC internal network. Grafana reads the generated metrics
through Control Plane's metrics integration.

## Signals

### Metrics

Metrics are aggregated numbers over time. They are the best default for
dashboards and alerts because they are fast to query and cheap to evaluate.

Good examples:

- request rate
- p95 request latency
- error count
- Sidekiq job count
- Redis operation count
- database operation latency
- container restart count

### Traces

Traces show a request or job broken into spans. They are best for investigating
why a request was slow or what dependency caused an error.

Good examples:

- Which DB query made this request slow?
- Which external API call timed out?
- Which Sidekiq job failed and what did it call?

### Logs

Logs are application events and messages. They are useful for details, but raw
log queries are often too expensive for broad dashboards. Prefer generating
targeted metrics from recurring log patterns.

Good examples:

- count a known error message
- correlate an app log with a trace id
- inspect the exact message after an alert fires

## Rails Application Setup

Add OpenTelemetry gems for the instrumentation libraries your app uses:

```ruby
# OpenTelemetry SDK and exporter
gem "opentelemetry-sdk"
gem "opentelemetry-exporter-otlp"

# Common Rails instrumentation
gem "opentelemetry-instrumentation-action_pack"
gem "opentelemetry-instrumentation-action_view"
gem "opentelemetry-instrumentation-active_job"
gem "opentelemetry-instrumentation-active_record"
gem "opentelemetry-instrumentation-active_support"
gem "opentelemetry-instrumentation-rack"
gem "opentelemetry-instrumentation-rails"

# Add only what your app actually uses
gem "opentelemetry-instrumentation-pg"
gem "opentelemetry-instrumentation-redis"
gem "opentelemetry-instrumentation-sidekiq"
gem "opentelemetry-instrumentation-faraday"
gem "opentelemetry-instrumentation-http"
```

Keep OpenTelemetry disabled by default until the collector is deployed and
reviewed:

```ruby
if ENV["ENABLE_OPEN_TELEMETRY"] == "true"
  require "opentelemetry/sdk"
  require "opentelemetry/exporter/otlp"

  collector = ENV.fetch("OPEN_TELEMETRY_COLLECTOR_ADDRESS", "http://localhost:4318")

  OpenTelemetry::SDK.configure do |config|
    config.service_name = ENV.fetch("OTEL_SERVICE_NAME") do
      ENV.fetch("CPLN_WORKLOAD", "rails-app")
    end

    exporter = OpenTelemetry::Exporter::OTLP::Exporter.new(
      endpoint: "#{collector}/v1/traces"
    )

    config.add_span_processor(
      OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(exporter)
    )

    config.use "OpenTelemetry::Instrumentation::Rack"
    config.use "OpenTelemetry::Instrumentation::Rails"
    config.use "OpenTelemetry::Instrumentation::ActionPack"
    config.use "OpenTelemetry::Instrumentation::ActionView"
    config.use "OpenTelemetry::Instrumentation::ActiveRecord"
    config.use "OpenTelemetry::Instrumentation::ActiveJob"
    config.use "OpenTelemetry::Instrumentation::ActiveSupport"
    config.use "OpenTelemetry::Instrumentation::PG"
    config.use "OpenTelemetry::Instrumentation::Redis"
    config.use "OpenTelemetry::Instrumentation::Sidekiq"
    config.use "OpenTelemetry::Instrumentation::Faraday"
    config.use "OpenTelemetry::Instrumentation::HTTP"
  end
end
```

This is a minimal shape. Production applications should also add resource
attributes that identify the Control Plane org, GVC, workload, replica, image,
and commit.

`OTEL_SERVICE_NAME` is the standard OpenTelemetry service name env var. Set it
per workload when possible. For simple apps, `config.use_all` can replace the
explicit `config.use` calls, but an explicit list makes copied examples easier
to review.

## Control Plane Resource Attributes

Control Plane workloads expose useful environment variables that can be copied
into OpenTelemetry resource attributes. These make dashboards filterable by org,
GVC, workload, replica, image, and commit.

Recommended attributes:

```text
original_cpln_org
original_cpln_gvc
original_cpln_workload
original_cpln_workload_version
original_cpln_replica
original_cpln_image
original_commit_hash
```

Use one helper module to derive these attributes, then reuse it for traces,
logs, and metrics.

## Collector Workload

Create an internal collector workload in the same GVC as the app workloads.

Recommended ports:

- `4318`: OTLP HTTP receiver
- `9292`: Prometheus metrics endpoint
- `55679`: zpages/debug endpoint, internal only

Recommended firewall:

- internal inbound: same GVC
- external inbound: none
- outbound: only what the collector needs

Recommended env:

```yaml
OPEN_TELEMETRY_COLLECTOR_RECEIVER_ENDPOINT: "0.0.0.0:4318"
OPEN_TELEMETRY_CONFIG: "cpln://secret/<collector-config-secret>"
OPEN_TELEMETRY_CONFIG_HASH: "<hash-of-config>"
```

Expose the collector's metrics endpoint to Control Plane:

```yaml
metrics:
  path: "/metrics"
  port: 9292
```

## Collector Config

Prefer small source files that build into one generated collector config. This
is much easier to review than one large YAML file.

Suggested structure:

```text
.controlplane/open_telemetry/
  build_main_collector_config
  check_main_collector_config
  validate_main_collector_config
  main_collector_config.yml
  main_collector_config/
    receivers/
    processors/
    connectors/
    exporters/
    service/
      pipelines/
```

Minimum collector config components:

- OTLP HTTP receiver
- transform processor for normalized span attributes
- spanmetrics connector for generated metrics
- Prometheus exporter
- batch processor
- zpages extension

Normalize span attributes before generating metrics:

```yaml
processors:
  transform/normalize:
    trace_statements:
      - statements:
          - set(span.attributes["instrumentation.name"], scope.name)
          - set(span.attributes["root_span"], true) where IsRootSpan()
          - set(span.attributes["root_span"], false) where not IsRootSpan()
          - set(span.attributes["resource.name"], span.name) where span.attributes["resource.name"] == nil
```

Generate a root request latency metric:

```yaml
connectors:
  spanmetrics/http_root_span_latency:
    namespace: http_root_span_latency
    dimensions:
      - name: service.name
      - name: original_cpln_workload
    exclude_dimensions:
      - span.name
      - span.kind
      - status.code
    histogram:
      explicit:
        buckets:
          - 5ms
          - 10ms
          - 50ms
          - 100ms
          - 250ms
          - 500ms
          - 1s
          - 2s
          - 5s
          - 10s
```

## Template Guidance

Start with an application-owned collector config. Promote pieces into reusable
Control Plane Flow templates only after at least two applications need the same
shape.

Good candidates for shared templates:

- internal collector workload definition
- standard OTLP receiver ports
- standard Prometheus metrics endpoint
- resource attribute normalization
- collector config hash environment variable
- validation script names and CI checks

Keep application-specific choices in the application repository:

- metric names and histogram buckets
- span filters
- log patterns converted into metrics
- dashboard panels and alert thresholds
- receiver/exporter settings that depend on traffic shape or compliance needs

## Rollout Order

Use a non-production GVC for the first rollout.

1. Add application OpenTelemetry gems and initializer behind
   `ENABLE_OPEN_TELEMETRY=false`.
2. Add collector config source files, generated config, and local validation
   scripts.
3. Add the internal collector workload with external ingress closed.
4. Deploy the collector while app telemetry is still disabled.
5. Confirm the collector starts cleanly and exposes `/metrics`.
6. Enable OpenTelemetry for one non-production app workload.
7. Confirm generated metrics appear at the collector `/metrics` endpoint.
8. Confirm Control Plane Grafana can query those metrics.
9. Draft the dashboard from queries or exported JSON and get human review before
   saving it in a shared Grafana folder.
10. Add alerts only after the dashboard queries are stable.

For production, repeat the same sequence with explicit approval, a written
rollback, and a short observation window after each change.

## Dashboard Starting Point

Start with a small dashboard. Do not begin by copying a large JSON dashboard
model.

Suggested rows:

1. Request overview
   - requests per second
   - p50/p95/p99 latency
   - error count and error rate

2. Workload health
   - CPU
   - memory
   - restarts
   - replica count

3. Dependencies
   - Postgres latency and operation count
   - Redis latency and operation count
   - external HTTP latency

4. Background jobs
   - job count
   - job latency
   - job errors

5. Logs and traces links
   - links or notes for drilldown, trace search, and log search

Dashboard review checklist:

- panel queries are scoped by service and workload
- variables use low-cardinality labels
- p95/p99 panels use histogram queries, not client-side percentile transforms
- dashboard JSON contains no secrets or customer identifiers
- dashboard folder and permissions are intentional
- changes are exported or recorded before saving over an existing dashboard

## Alert Starting Point

Start with low-noise alerts:

- container restarts
- sustained high memory usage
- sustained high request error rate
- request latency above a reviewed threshold
- Rack timeout count
- collector unhealthy or no metrics arriving

Avoid broad anomaly alerts until the baseline is understood. Week-over-week
comparison can be useful, but it can also be noisy when traffic shifts by a few
minutes or has bot contamination.

Alert review checklist:

- every alert has a named owner
- every threshold has a short reason
- every page has a tested runbook or rollback note
- new alerts route to a test or non-paging contact point first
- production paging changes are approved separately from dashboard changes

## Validation

Before deploying:

```sh
# Replace with your app's actual OpenTelemetry spec path.
bundle exec rspec spec/open_telemetry/

# Replace with your app's actual collector validation script names.
./script/check_open_telemetry_config
./script/validate_open_telemetry_config
```

Before enabling in staging:

- app boots with OpenTelemetry disabled
- app boots with OpenTelemetry enabled
- collector starts and passes readiness checks
- collector `/metrics` endpoint has generated samples
- Grafana can query the metrics
- disabling OpenTelemetry is enough to roll back app-side impact

Before enabling in production:

- staging has run long enough to observe collector CPU and memory
- dashboards are reviewed by a human
- alerts are routed to a non-paging or test contact point first
- rollback steps are written down
- production approval is explicit

## Safety Notes

- Treat Grafana dashboards and alert rules as production-impacting settings.
- Export or draft dashboard JSON before saving live dashboards.
- Use non-production apps for first rollout.
- Keep collector external ingress closed unless a specific receiver requires it.
- Do not put secrets in dashboard JSON, templates, or screenshots.
- Keep high-cardinality attributes out of metric dimensions.
- Prefer labels such as workload, service, and version; avoid user IDs, URLs
  with IDs, raw SQL, request IDs, or trace IDs as metric dimensions.
