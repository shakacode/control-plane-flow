resource "cpln_workload" "workload" {
  type = var.type

  gvc = var.gvc
  identity_link = var.identity_link

  name = var.name
  description = var.description

  tags = var.tags
  support_dynamic_tags = var.support_dynamic_tags

  dynamic "container" {
    for_each = var.containers
    iterator = container
    content {
      name = container.key

      args = container.value.args
      command = container.value.command
      env = container.value.envs
      image = container.value.image

      cpu = container.value.cpu
      memory = container.value.memory

      dynamic "lifecycle" {
        for_each = container.value.post_start_command != null || container.value.pre_stop_command != null ? [1] : []
        content {
          dynamic "post_start" {
            for_each = container.value.post_start_command != null ? [1] : []
            content {
              exec {
                command = [
                  "/bin/bash",
                  "-c",
                  "[ -f ${container.value.post_start_command} ] && ${container.value.post_start_command} || true",
                ]
              }
            }
          }
          dynamic "pre_stop" {
            for_each = container.value.pre_stop_command != null ? [1] : []
            content {
              exec {
                command = [
                  "/bin/bash",
                  "-c",
                  "[ -f ${container.value.pre_stop_command} ] && ${container.value.pre_stop_command} || true",
                ]
              }
            }
          }
        }
      }

      dynamic "liveness_probe" {
        for_each = container.value.liveness_probe != null ? [container.value.liveness_probe] : []
        iterator = liveness
        content {
          dynamic "exec" {
            for_each = liveness.value.exec != null ? [liveness.value.exec] : []
            iterator = exec
            content {
              command = exec.value.command
            }
          }
          dynamic "http_get" {
            for_each = liveness.value.http_get != null ? [liveness.value.http_get] : []
            iterator = http_get
            content {
              path = http_get.value.path
              port = http_get.value.port
              scheme = http_get.value.scheme
              http_headers = http_get.value.http_headers
            }
          }
          dynamic "tcp_socket" {
            for_each = liveness.value.tcp_socket != null ? [liveness.value.tcp_socket] : []
            iterator = tcp_socket
            content {
              port = tcp_socket.value.port
            }
          }
          dynamic "grpc" {
            for_each = liveness.value.grpc != null ? [liveness.value.grpc] : []
            iterator = grpc
            content {
              port = grpc.value.port
            }
          }
          failure_threshold = liveness.value.failure_threshold
          initial_delay_seconds = liveness.value.initial_delay_seconds
          period_seconds = liveness.value.period_seconds
          success_threshold = liveness.value.success_threshold
          timeout_seconds = liveness.value.timeout_seconds
        }
      }

      dynamic "readiness_probe" {
        for_each = container.value.readiness_probe != null ? [container.value.readiness_probe] : []
        iterator = readiness
        content {
          dynamic "exec" {
            for_each = readiness.value.exec != null ? [readiness.value.exec] : []
            iterator = exec
            content {
              command = exec.value.command
            }
          }
          dynamic "http_get" {
            for_each = readiness.value.http_get != null ? [readiness.value.http_get] : []
            iterator = http_get
            content {
              path = http_get.value.path
              port = http_get.value.port
              scheme = http_get.value.scheme
              http_headers = http_get.value.http_headers
            }
          }
          dynamic "tcp_socket" {
            for_each = readiness.value.tcp_socket != null ? [readiness.value.tcp_socket] : []
            iterator = tcp_socket
            content {
              port = tcp_socket.value.port
            }
          }
          dynamic "grpc" {
            for_each = readiness.value.grpc != null ? [readiness.value.grpc] : []
            iterator = grpc
            content {
              port = grpc.value.port
            }
          }
          failure_threshold = readiness.value.failure_threshold
          initial_delay_seconds = readiness.value.initial_delay_seconds
          period_seconds = readiness.value.period_seconds
          success_threshold = readiness.value.success_threshold
          timeout_seconds = readiness.value.timeout_seconds
        }
      }

      dynamic "ports" {
        for_each = container.value.ports
        iterator = port
        content {
          number = port.value.number
          protocol = port.value.protocol
        }
      }

      dynamic "volume" {
        for_each = container.value.volumes
        iterator = volume
        content {
          uri = volume.value.uri
          path = volume.value.path
        }
      }
    }
  }

  dynamic "options" {
    for_each = var.options != null ? [var.options] : []
    iterator = options
    content {
      dynamic "autoscaling" {
        for_each = options.value.autoscaling != null ? [options.value.autoscaling] : []
        iterator = autoscaling
        content {
          metric = autoscaling.value.metric
          metric_percentile = autoscaling.value.metric_percentile
          max_scale = autoscaling.value.max_scale
          min_scale = autoscaling.value.min_scale
          target = autoscaling.value.target
          scale_to_zero_delay = autoscaling.value.scale_to_zero_delay
          max_concurrency = autoscaling.value.max_concurrency
        }
      }
      capacity_ai = options.value.capacity_ai
      suspend = options.value.suspend
      timeout_seconds = options.value.timeout_seconds
      debug = options.value.debug
    }
  }

  dynamic "local_options" {
    for_each = var.local_options != null ? [var.local_options] : []
    iterator = options
    content {
      dynamic "autoscaling" {
        for_each = options.value.autoscaling != null ? [options.value.autoscaling] : []
        iterator = autoscaling
        content {
          metric = autoscaling.value.metric
          metric_percentile = autoscaling.value.metric_percentile
          max_scale = autoscaling.value.max_scale
          min_scale = autoscaling.value.min_scale
          target = autoscaling.value.target
          scale_to_zero_delay = autoscaling.value.scale_to_zero_delay
          max_concurrency = autoscaling.value.max_concurrency
        }
      }
      location = options.value.location
      capacity_ai = options.value.capacity_ai
      suspend = options.value.suspend
      timeout_seconds = options.value.timeout_seconds
      debug = options.value.debug
    }
  }

  dynamic "rollout_options" {
    for_each = var.rollout_options != null ? [var.rollout_options] : []
    iterator = rollout_options
    content {
      min_ready_seconds = rollout_options.value.min_ready_seconds
      max_unavailable_replicas = rollout_options.value.max_unavailable_replicas
      max_surge_replicas = rollout_options.value.max_surge_replicas
      scaling_policy = rollout_options.value.scaling_policy
    }
  }

  dynamic "security_options" {
    for_each = var.security_options != null ? [var.security_options] : []
    iterator = security_options
    content {
      file_system_group_id = security_options.value.file_system_group_id
    }
  }

  dynamic "firewall_spec" {
    for_each = var.firewall_spec != null ? [var.firewall_spec] : []
    iterator = firewall_spec
    content {
      dynamic "external" {
        for_each = firewall_spec.value.external != null ? [firewall_spec.value.external] : []
        iterator = external
        content {
          inbound_allow_cidr = external.value.inbound_allow_cidr
          outbound_allow_hostname = external.value.outbound_allow_hostname
          outbound_allow_cidr = external.value.outbound_allow_cidr
          dynamic "outbound_allow_port" {
            for_each = external.value.outbound_allow_port
            iterator = outbound_allow_port
            content {
              protocol = outbound_allow_port.value.protocol
              number = outbound_allow_port.value.number
            }
          }
        }
      }
      dynamic "internal" {
        for_each = firewall_spec.value.internal != null ? [firewall_spec.value.internal] : []
        iterator = internal
        content {
          inbound_allow_type = internal.value.inbound_allow_type
          inbound_allow_workload = internal.value.inbound_allow_workload
        }
      }
    }
  }

  dynamic "load_balancer" {
    for_each = var.load_balancer != null ? [var.load_balancer] : []
    iterator = load_balancer
    content {
      dynamic "direct" {
        for_each = load_balancer.value.direct != null ? [load_balancer.value.direct] : []
        iterator = direct
        content {
          enabled = direct.value.enabled
          dynamic "port" {
            for_each = direct.value.port
            iterator = port
            content {
              external_port = port.value.external_port
              protocol = port.value.protocol
              scheme = port.value.scheme
              container_port = port.value.container_port
            }
          }
        }
      }
      dynamic "geo_location" {
        for_each = load_balancer.value.geo_location != null ? [load_balancer.value.geo_location] : []
        iterator = geo_location
        content {
          enabled = geo_location.value.enabled
          dynamic "headers" {
            for_each = geo_location.value.headers != null ? [geo_location.value.headers] : []
            iterator = headers
            content {
              asn = headers.value.asn
              city = headers.value.city
              country = headers.value.country
              region = headers.value.region
            }
          }
        }
      }
    }
  }

  dynamic "job" {
    for_each = var.job != null ? [var.job] : []
    iterator = job
    content {
      schedule = job.value.schedule
      concurrency_policy = job.value.concurrency_policy
      history_limit = job.value.history_limit
      restart_policy = job.value.restart_policy
      active_deadline_seconds = job.value.active_deadline_seconds
    }
  }
}
