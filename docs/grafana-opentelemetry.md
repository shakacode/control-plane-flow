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

For the generic Control Plane telemetry template shape, start with
[Telemetry](/docs/telemetry/) and
[Collector Workload](/docs/telemetry/collector.md). This guide is the Rails and
Grafana companion: it focuses on application instrumentation, spanmetrics,
dashboards, and alerting.

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
targeted metrics from recurring log patterns. See [Tips: Logs](/docs/tips.md#logs)
for querying Control Plane logs directly.

Good examples:

- count a known error message
- correlate an app log with a trace id
- inspect the exact message after an alert fires

## Rails Application Setup

Add OpenTelemetry gems for the instrumentation libraries your app uses:

```ruby
# Adjust this group to match where the app emits telemetry.
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

Use the Bundler group that matches where the app will emit telemetry —
`:production` above is only an example, and many Control Plane deployments run
with production gems even for QA or staging. If you need to test OpenTelemetry
locally or in CI, include the same gems in those Bundler groups too;
`require: false` keeps them unloaded until the initializer guard enables
telemetry.

Keep OpenTelemetry disabled by default until the collector is deployed and
reviewed. The `ENABLE_OPEN_TELEMETRY` flag below is a custom application guard,
not a standard OpenTelemetry environment variable; use it only when this
initializer reads that flag. Otherwise, rely on your app's own rollout guard plus
standard SDK variables such as `OTEL_SERVICE_NAME` and
`OTEL_EXPORTER_OTLP_ENDPOINT`, as described in
[Application Instrumentation](/docs/telemetry/application-instrumentation.md).
Place this in a Rails initializer such as
`config/initializers/opentelemetry.rb` so the Rails instrumentation hooks into
the framework boot sequence:

```ruby
if ENV["ENABLE_OPEN_TELEMETRY"] == "true"
  # Require only the instrumentation gems you added to the Gemfile above. A
  # require without a matching gem raises LoadError at boot.
  require "opentelemetry/sdk"
  require "opentelemetry/exporter/otlp"
  require "opentelemetry/instrumentation/rails"
  require "opentelemetry/instrumentation/pg"
  require "opentelemetry/instrumentation/redis"
  require "opentelemetry/instrumentation/sidekiq"
  require "opentelemetry/instrumentation/faraday"
  require "opentelemetry/instrumentation/http"

  OpenTelemetry::SDK.configure do |config|
    # Set "service.name" directly in the resource so the complete resource is
    # defined in one place and does not depend on SDK merge order between
    # config.service_name= and config.resource=.
    resource_attributes = {
      "service.name" => ENV.fetch("OTEL_SERVICE_NAME") { ENV.fetch("CPLN_WORKLOAD", "rails-app") },
      "original_cpln_org" => ENV["CPLN_ORG"],
      "original_cpln_gvc" => ENV["CPLN_GVC"],
      "original_cpln_workload" => ENV["CPLN_WORKLOAD"],
      "original_cpln_replica" => ENV["CPLN_REPLICA"],
      "original_cpln_image" => ENV["CPLN_IMAGE"],
      "original_commit_hash" => ENV["APP_COMMIT_SHA"]
    }.compact

    config.resource = OpenTelemetry::SDK::Resources::Resource.create(resource_attributes)

    # The exporter reads OTEL_EXPORTER_OTLP_ENDPOINT and
    # OTEL_EXPORTER_OTLP_PROTOCOL from the environment — see the notes below.
    exporter = OpenTelemetry::Exporter::OTLP::Exporter.new

    config.add_span_processor(
      OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(exporter)
    )

    config.use "OpenTelemetry::Instrumentation::Rails"
    config.use "OpenTelemetry::Instrumentation::PG", { db_statement: :obfuscate }
    config.use "OpenTelemetry::Instrumentation::Redis", { db_statement: :obfuscate }
    config.use "OpenTelemetry::Instrumentation::Sidekiq"
    config.use "OpenTelemetry::Instrumentation::Faraday"
    config.use "OpenTelemetry::Instrumentation::HTTP"
  end
end
```

`APP_COMMIT_SHA` is a custom application variable, not a Control Plane injected
variable. Set it at image build time or replace it with a helper that derives the
commit from the image tag.

Recommended app workload env:

```yaml
env:
  # ENABLE_OPEN_TELEMETRY is a custom application guard used by the initializer
  # above. Set it only after the collector is deployed, or replace it with the
  # rollout guard your application already uses.
  # - name: ENABLE_OPEN_TELEMETRY
  #   value: "true"
  - name: OTEL_SERVICE_NAME
    value: "<workload-name>"
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://open-telemetry-collector.{{APP_NAME}}.cpln.local:4318"
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: "http/protobuf"
```

`OTEL_SERVICE_NAME` is the standard OpenTelemetry service name env var; set it
per workload when possible. `OTEL_EXPORTER_OTLP_ENDPOINT` must be a collector
base URL using the internal collector workload hostname in the same GVC — not
`localhost` and not a signal-specific path such as `/v1/traces`. The generic
telemetry docs use `open-telemetry-collector.{{APP_NAME}}.cpln.local`;
`cpflow apply-template` replaces `{{APP_NAME}}` with the deployed app name. If
you apply the YAML directly, replace it manually or keep an equivalent internal
hostname if your collector workload is named differently. Without these env vars
the exporter defaults to
`http://localhost:4318`, which usually does not exist on a Control Plane
workload, so spans are dropped silently. (Port 4317 is the gRPC default and
applies to the separate `opentelemetry-exporter-otlp-grpc` gem, which this
guide does not use.)

The `opentelemetry-instrumentation-http` gem instruments the `http.rb` client.
Apps that use `Net::HTTP`, HTTParty, Excon, Typhoeus, or another HTTP client
should choose the matching OpenTelemetry instrumentation gem instead.

## Control Plane Resource Attributes

Control Plane workloads expose useful environment variables that can be copied
into OpenTelemetry resource attributes. These make dashboards filterable by org,
GVC, workload, replica, image, and commit.

Use a consistent prefix such as `original_` to distinguish the resource
attribute names from raw Control Plane env vars like `CPLN_ORG`, `CPLN_GVC`,
`CPLN_WORKLOAD`, `CPLN_REPLICA`, and `CPLN_IMAGE`. Whatever prefix you choose,
keep one naming convention per app so dashboards and trace queries stay
predictable.

The initializer above sets the recommended attributes. Use one helper module to
derive them, then reuse it for traces, logs, and metrics. Keep `original_cpln_replica`, `original_cpln_image`, and
`original_commit_hash` out of generated Prometheus metric dimensions; they are
useful on traces but too high-cardinality for ordinary dashboard labels.

## Collector Workload

Create an internal collector workload in the same GVC as the app workloads.
Use [Collector Workload](/docs/telemetry/collector.md) as the canonical template
for workload shape, identity, secret policy, config delivery, and port/config
alignment. The values below are a Rails/Grafana starter profile layered on top of
that template.

Recommended ports:

- `4318`: OTLP HTTP receiver
- `9292`: Prometheus metrics endpoint
- `55679`: zpages/debug endpoint, internal only

Use the [Collector Workload firewall example](/docs/telemetry/collector.md#control-plane-workload-template)
as the canonical YAML shape. For this Rails/Grafana profile, keep internal
inbound limited to the same GVC, external ingress closed, and outbound egress
limited to the telemetry backend hostnames or CIDRs the collector needs.

Recommended starter container resources:

```yaml
containers:
  - name: open-telemetry-collector
    cpu: 250m
    memory: 512Mi
```

Tune CPU and memory from staging observations before production rollout.

Recommended env:

```yaml
env:
  # Custom backend variables, not standard OpenTelemetry env vars. The collector
  # reads them through ${env:VAR} substitution in the config YAML, so each must be
  # referenced as ${env:TELEMETRY_...} in that config to take effect.
  - name: TELEMETRY_BACKEND_TOKEN
    value: "cpln://secret/{{APP_NAME}}-telemetry-backend.TELEMETRY_BACKEND_TOKEN"
```

The `cpln://secret/<dictionary-name>.<KEY>` reference syntax is documented in
[Secrets and ENV Values](/docs/secrets-and-env-values.md). If you mount config
from a dictionary secret instead of baking it into the image, include the
dictionary key suffix as well, for example
`cpln://secret/<collector-config-secret>.CONFIG_YAML`. When the collector config
changes, update the mounted secret or image and run
`cpflow ps:restart -a $APP_NAME -w open-telemetry-collector` so the workload
loads the new config.

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
- memory limiter processor
- transform processor for normalized span attributes
- spanmetrics connector for generated metrics
- Prometheus exporter
- batch processor
- zpages extension

Pin the collector image, and validate the generated config against that exact
image before deployment — OTTL and spanmetrics feature support varies by
collector-contrib version.

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

`IsRootSpan()` requires collector-contrib v0.105.0 or later (added in
[contrib #32918](https://github.com/open-telemetry/opentelemetry-collector-contrib/pull/32918)).
On an older pinned image, replace the two `IsRootSpan()` lines with an explicit
parent-span-id check — a root span has a zero parent span ID — and validate it
against that exact image:

```yaml
- set(attributes["root_span"], true) where parent_span_id == SpanID(0x0000000000000000)
- set(attributes["root_span"], false) where parent_span_id != SpanID(0x0000000000000000)
```

Generate a request latency metric from selected root spans. One safe pattern is
to run a filter processor before the spanmetrics connector that drops spans where
the normalized `root_span` attribute is not true:

```yaml
processors:
  filter/non_root_spans:
    error_mode: propagate
    traces:
      span:
        - 'attributes["root_span"] != true'
```

The filter processor drops spans that match the condition. `error_mode: ignore`
logs expression errors and continues, while `silent` continues without logging.
For this filter, either mode can turn a broken condition into a no-op that passes
every span — including child spans — into the spanmetrics connector, inflating
metric cardinality. Keep `error_mode: propagate` in development and staging, and
include a known trace with one root span and one child span in collector
validation. Keep `propagate` as the default production setting too: OTTL
evaluation errors and dropped payloads are easier to alert on than a no-op filter
that floods spanmetrics with child spans. If a team deliberately chooses
`ignore`, do it only after the OTTL-error and dropped-span alerts in
[Alert Starting Point](#alert-starting-point) are active and routed to an owner.

Processor order is load-bearing here. The condition `attributes["root_span"] != true`
matches spans where the attribute is **absent** as well as where it is `false`, so
`transform/normalize` (which sets `root_span`) must run before `filter/non_root_spans`
in the traces pipeline. Reversed — or with a misconfigured transform — the filter
drops every span with no error or warning. The `service.pipelines` example below
shows the required order.

Duration-string buckets and `exclude_dimensions` require collector-contrib
images that support those spanmetrics schemas. If an app pins an older collector,
use float-second buckets such as `0.005`, `0.010`, and `1.0`, and remove
unsupported fields.

Then feed the filtered trace stream into the connector:

```yaml
connectors:
  spanmetrics/http_root_span_latency:
    namespace: http_root_span_latency
    dimensions:
      - name: service.name
      - name: original_cpln_workload
      - name: http.route
    exclude_dimensions:
      - span.name
      - span.kind
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

`span.name` and `span.kind` are excluded because raw Rails span names can carry
too much cardinality and the root-span filter makes span kind redundant for this
dashboard. The spanmetrics connector emits status code as a default dimension
(`status.code`, or `otel.status_code` when that feature gate is enabled), so do
not add it again under `dimensions`. Compute error rate from the connector's
request-count series split by that status-code label (errored calls ÷ total
calls), and confirm the exact metric and label names against your collector image
since they vary by spanmetrics version. OpenTelemetry sets server span status to
`Error` for 5xx but not 4xx — add `http.response.status_code` as a dimension if
you need 4xx granularity. Before enabling the connector, inspect `http.route`
values in a real staging trace and confirm they are route patterns such as
`/users/:id`, not raw request paths such as `/users/12345` — raw paths are one of
the most common causes of a spanmetrics setup overwhelming Prometheus storage.

Wire the receiver, processors, connector, and exporters together in one generated
collector config, with the processor order described above. The minimal example
below includes the top-level component stubs referenced by `service.pipelines`;
the spanmetrics connector terminates the traces pipeline and feeds the metrics
pipeline. The focused snippets above are repeated here intentionally so this
block can be copied as one complete starting point; keep the focused snippets and
this consolidated example in sync when changing processor names, filters, or
histogram buckets:

```yaml
receivers:
  otlp:
    protocols:
      http:
        endpoint: "0.0.0.0:4318"

processors:
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80
    spike_limit_percentage: 20

  transform/normalize:
    trace_statements:
      - context: span
        statements:
          - set(attributes["instrumentation.name"], instrumentation_scope.name)
          - set(attributes["root_span"], true) where IsRootSpan()
          - set(attributes["root_span"], false) where not IsRootSpan()

  filter/non_root_spans:
    error_mode: propagate
    traces:
      span:
        - 'attributes["root_span"] != true'

  batch: {}

connectors:
  spanmetrics/http_root_span_latency:
    namespace: http_root_span_latency
    dimensions:
      - name: service.name
      - name: original_cpln_workload
      - name: http.route
    exclude_dimensions:
      - span.name
      - span.kind
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

exporters:
  prometheus:
    endpoint: "0.0.0.0:9292"

extensions:
  zpages:
    endpoint: "0.0.0.0:55679"

service:
  extensions:
    - zpages
  pipelines:
    traces:
      receivers:
        - otlp
      processors:
        - memory_limiter
        - transform/normalize
        - filter/non_root_spans
        - batch
      exporters:
        - spanmetrics/http_root_span_latency
    metrics:
      receivers:
        - spanmetrics/http_root_span_latency
      processors:
        - memory_limiter
        - batch
      exporters:
        - prometheus
```

The spanmetrics connector is listed as an exporter on the traces pipeline and as
a receiver on the metrics pipeline; that shared reference is what links the two.
Every extension named under `service.extensions` also needs a matching top-level
`extensions:` block — shown here for `zpages` — or the collector fails to start.

In this minimal pipeline the spanmetrics connector is the only span consumer:
the filter discards every child span (database, Redis, Sidekiq, HTTP clients)
after the app has paid to generate and export it, and no raw traces are stored.
This config is metrics-only — the trace-drilldown use cases in
[Signals: Traces](#traces) (which DB query was slow, which external call timed
out) are not available with it alone. Enable only the instrumentation whose
spans a pipeline consumes, and to keep traces for debugging, add a trace
exporter (for example OTLP to Grafana Tempo) on the traces pipeline alongside
the spanmetrics connector.

At production request rates, generating and exporting 100% of spans before
filtering can overload the collector and inflate egress cost. For high-traffic
workloads, consider head-based sampling in the app
(`OTEL_TRACES_SAMPLER`, e.g. `parentbased_traceidratio`) or a tail-sampling
processor in the collector.

## Template Guidance

Start with an application-owned collector config. Promote pieces into reusable
Control Plane Flow templates only after at least two applications need the same
shape.

Good candidates for shared templates:

- internal collector workload definition
- standard OTLP receiver ports
- standard Prometheus metrics endpoint
- resource attribute normalization
- validation script names and CI checks

Keep application-specific choices in the application repository:

- metric names and histogram buckets
- span filters
- log patterns converted into metrics
- dashboard panels and alert thresholds
- receiver/exporter settings that depend on traffic shape or compliance needs

## Rollout Order

Use a non-production GVC for the first rollout.

1. Add application OpenTelemetry gems and initializer. If you use the custom
   `ENABLE_OPEN_TELEMETRY` guard above, leave it unset so the initializer guard
   keeps telemetry disabled.
2. Add collector config source files, generated config, and local validation
   scripts.
3. Add the internal collector workload with external ingress closed.
4. Deploy the collector while app telemetry is still disabled.
5. Confirm the collector starts cleanly and exposes `/metrics`.
6. Choose and record the non-production sampling setting before enabling app
   spans. Start low for high-traffic workloads, then adjust after collector CPU,
   memory, and egress are visible.
7. Enable OpenTelemetry for one non-production app workload.
8. Confirm generated metrics appear at the collector `/metrics` endpoint.
9. Confirm Control Plane Grafana can query those metrics.
10. Draft the dashboard from queries or exported JSON and get human review before
   saving it in a shared Grafana folder.
11. Add alerts only after the dashboard queries are stable.

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
- collector span throughput spiking above baseline, or the filter's dropped-span
  count falling to zero — an early signal that a transform/filter regression is
  passing child spans into spanmetrics (metric names vary by collector version)

The [RAM](/docs/tips.md#ram) and [CPU](/docs/tips.md#cpu) sections in Tips walk
through creating the memory, restart, and CPU alerts in Grafana.

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
./.controlplane/open_telemetry/check_main_collector_config
./.controlplane/open_telemetry/validate_main_collector_config
```

Before enabling in staging:

- app boots with OpenTelemetry disabled
- app boots with OpenTelemetry enabled
- collector starts and passes readiness checks
- collector `/metrics` endpoint has generated samples
- `http.route` in a staging trace shows route patterns (`/users/:id`), not raw
  paths, before enabling the spanmetrics connector
- Grafana can query the metrics
- disabling OpenTelemetry is enough to roll back app-side impact

Before enabling in production:

- staging has run long enough to observe collector CPU and memory
- sampling is explicitly configured and reviewed for expected traffic, egress,
  and metric accuracy
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
- Keep high-cardinality attributes — user IDs, URLs with IDs, raw SQL, request
  IDs, trace IDs — out of metric dimensions; prefer labels such as workload,
  service, and version.
