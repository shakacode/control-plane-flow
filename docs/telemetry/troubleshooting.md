# Telemetry Troubleshooting

Use this checklist when telemetry does not appear in the backend.

## 1. Confirm Workloads

```sh
cpflow ps -a $APP_NAME -w open-telemetry-collector
cpflow ps -a $APP_NAME -w app
```

Replace `app` with the workload you are checking.

## 2. Check Collector Logs

```sh
cpflow logs -a $APP_NAME -w open-telemetry-collector
```

Look for:

- config parse errors
- receiver bind failures
- exporter authentication failures
- backend DNS or connection failures
- dropped data due to memory or queue limits

## 3. Check Application Logs

```sh
cpflow logs -a $APP_NAME -w app
```

Look for exporter errors from the application SDK. Common causes are:

- wrong `OTEL_EXPORTER_OTLP_ENDPOINT`
- app instrumentation not enabled
- collector service name typo
- unsupported protocol value
- backend token missing from the collector

## 4. Verify Port Agreement

The Control Plane workload template and collector config must agree.

| Symptom | Check |
| --- | --- |
| App cannot export OTLP | Workload exposes `4318`; collector binds `0.0.0.0:4318` |
| StatsD metrics missing | Workload exposes `9127`; collector has `statsd/tcp` on `0.0.0.0:9127` |
| Prometheus scrape empty | Workload exposes `9292`; collector has `prometheus` exporter on `0.0.0.0:9292` |

## 5. Verify DNS

From an app workload shell, check that the collector service name resolves:

```sh
getent hosts open-telemetry-collector.$APP_NAME.cpln.local
```

If your image does not include `getent`, use an equivalent DNS tool available in
the image.

## 6. Keep The First Test Simple

Before adding sampling, filtering, derived metrics, or multiple exporters:

1. Start with one app workload.
2. Send OTLP traces over HTTP.
3. Export to a debug exporter or one known backend.
4. Confirm data appears.
5. Add metrics and logs after traces work.

Small steps make it much easier to tell whether the app, collector, network, or
backend is the source of the problem.
