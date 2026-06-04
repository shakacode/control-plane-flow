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
group :production do
  # OpenTelemetry SDK and exporter
  gem "opentelemetry-sdk", require: false
  gem "opentelemetry-exporter-otlp", require: false

  # Rails instrumentation registers the Rails framework pieces once.
  gem "opentelemetry-instrumentation-rails", require: false

  # Add only what your app actually uses.
  gem "opentelemetry-instrumentation-pg", require: false
  gem "opentelemetry-instrumentation-redis", require: false
  gem "opentelemetry-instrumentation-sidekiq", require: false
  gem "opentelemetry-instrumentation-faraday", require: false
  gem "opentelemetry-instrumentation-http", require: false
end
```

Use the Bundler group that matches where the app will emit telemetry. Many
Control Plane deployments run with production gems even for QA or staging. If
you need to test OpenTelemetry locally or in CI, include the same gems in those
Bundler groups too; `require: false` keeps them unloaded until the initializer
guard enables telemetry.

Keep OpenTelemetry disabled by default until the collector is deployed and
reviewed:

```ruby
if ENV["ENABLE_OPEN_TELEMETRY"] == "true"
  require "opentelemetry/sdk"
  require "opentelemetry/exporter/otlp"
  require "opentelemetry/instrumentation/rails"
  require "opentelemetry/instrumentation/pg"
  require "opentelemetry/instrumentation/redis"
  require "opentelemetry/instrumentation/sidekiq"
  require "opentelemetry/instrumentation/faraday"
  require "opentelemetry/instrumentation/http"

  ENV["OTEL_EXPORTER_OTLP_ENDPOINT"] = "http://localhost:4318" if ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].to_s.empty?
  ENV["OTEL_EXPORTER_OTLP_PROTOCOL"] = "http/protobuf" if ENV["OTEL_EXPORTER_OTLP_PROTOCOL"].to_s.empty?

  OpenTelemetry::SDK.configure do |config|
    config.service_name = ENV.fetch("OTEL_SERVICE_NAME") do
      ENV.fetch("CPLN_WORKLOAD", "rails-app")
    end

    exporter = OpenTelemetry::Exporter::OTLP::Exporter.new

    config.add_span_processor(
      OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(exporter)
    )

    config.use "OpenTelemetry::Instrumentation::Rails"
    config.use "OpenTelemetry::Instrumentation::PG", { db_statement: :obfuscate }
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
per workload when possible. `OTEL_EXPORTER_OTLP_ENDPOINT` should be a collector
base URL such as `http://otel-collector:4318`, not a signal-specific path such
as `/v1/traces`.

## Control Plane Resource Attributes

Control Plane workloads expose useful environment variables that can be copied
into OpenTelemetry resource attributes. These make dashboards filterable by org,
GVC, workload, replica, image, and commit.

Use a consistent prefix such as `original_` to distinguish the resource
attribute names from raw Control Plane env vars like `CPLN_ORG`, `CPLN_GVC`,
`CPLN_WORKLOAD`, `CPLN_REPLICA`, and `CPLN_IMAGE`. A future shared template may
choose a `cpln.` namespace, but keep one naming convention per app so dashboards
and trace queries stay predictable.

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
logs, and metrics. Keep `original_cpln_replica`, `original_cpln_image`, and
`original_commit_hash` out of generated Prometheus metric dimensions; they are
useful on traces but too high-cardinality for ordinary dashboard labels.

## Collector Workload

Create an internal collector workload in the same GVC as the app workloads.

Recommended ports:

- `4318`: OTLP HTTP receiver
- `8889`: Prometheus metrics endpoint
- `55679`: zpages/debug endpoint, internal only

Recommended firewall:

- internal inbound: same GVC
- external inbound: none
- outbound: only what the collector needs

Recommended env:

```yaml
# Custom app variables, not standard OpenTelemetry env vars.
OPEN_TELEMETRY_COLLECTOR_RECEIVER_ENDPOINT: "0.0.0.0:4318"
OPEN_TELEMETRY_CONFIG: "cpln://secret/<collector-config-secret>"
# Set to a hash of the config content so secret updates force a workload spec
# change and collector restart.
OPEN_TELEMETRY_CONFIG_HASH: "<hash-of-config>"
```

Expose the collector's metrics endpoint to Control Plane:

```yaml
metrics:
  path: "/metrics"
  port: 8889
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
      - context: span
        statements:
          - set(attributes["instrumentation.name"], instrumentation_scope.name)
          - set(attributes["root_span"], true) where IsRootSpan()
          - set(attributes["root_span"], false) where not IsRootSpan()
```

Generate a request latency metric from selected root spans. One safe pattern is
to run a filter processor before the spanmetrics connector that drops spans where
the normalized `root_span` attribute is not true. Validate this condition with
the collector binary used by the app before rollout:

```yaml
processors:
  filter/non_root_spans:
    error_mode: ignore
    traces:
      span:
        - 'attributes["root_span"] != true'
```

Then feed the filtered trace stream into the connector:

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

1. Add application OpenTelemetry gems and initializer. Leave
   `ENABLE_OPEN_TELEMETRY` unset so the initializer guard keeps telemetry
   disabled.
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
