# Telemetry Troubleshooting

Use this checklist when telemetry does not appear in the backend.

Set `APP_NAME` before running the examples:

```sh
APP_NAME=your-app-name
```

## 1. Confirm Workloads

```sh
cpflow ps -a $APP_NAME -w open-telemetry-collector
cpflow ps -a $APP_NAME -w app
```

Replace `app` with the workload you are checking.

`cpflow ps` lists running replicas. If the collector is deployed but scaled to
zero, restart or scale it before debugging collector config or application
exporter settings.

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
getent hosts open-telemetry-collector.${APP_NAME}.cpln.local
```

Set `APP_NAME` to the actual app name. If your image does not include `getent`,
use an equivalent DNS tool available in the image.

## 6. Keep The First Test Simple

Before adding sampling, filtering, derived metrics, or multiple exporters:

1. Start with one app workload.
2. Send OTLP traces over HTTP.
3. Export to a debug exporter or one known backend. To enable the debug
   exporter, uncomment the `debug:` block in your collector config, add `debug`
   to the relevant pipeline exporters list, and rebuild or remount the config.
   Remove the debug exporter before production use; it writes full telemetry
   payloads to collector logs.
4. Confirm data appears.
5. Add metrics and logs after traces work.

Use the debug exporter only for short validation windows. It writes full
telemetry payloads to collector logs, so remove or disable it before sending
production traffic or attributes that may contain sensitive data.

Small steps make it much easier to tell whether the app, collector, network, or
backend is the source of the problem.
