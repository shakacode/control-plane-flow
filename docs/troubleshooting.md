# Troubleshooting


## App Web Page Shows `upstream request timeout`

If you get a blank screen showing the message `upstream request timeout` on your app after running `cpflow open -a my-app-name`, check out the application logs. Your image has been promoted and your app crashing when starting.

## `502 Bad Gateway` with "protocol error" (Rails + Thruster)

If a Rails app fronted by [Thruster](https://github.com/basecamp/thruster) returns `502 Bad Gateway` with a "protocol error" message, the workload port is likely set to `protocol: http2`.

Thruster speaks HTTP/1.1 to upstreams, so the workload port must be `protocol: http`. Control Plane's load balancer still serves HTTP/2 to end users.

See [Thruster HTTP/2 Proxy on Control Plane](./thruster.md) for the full configuration and debugging commands.
