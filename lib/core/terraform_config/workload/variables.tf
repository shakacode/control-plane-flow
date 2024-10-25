variable "containers" {
  type = map(
    object({
      args = optional(list(string))
      command = optional(string)
      image = string

      inherit_env = optional(bool)
      envs = optional(map(string))

      cpu = optional(string, "1000m")
      memory = optional(string, "2048Mi")

      ports = optional(
        list(
          object({
            number = number
            protocol = string
          })
        ),
        [],
      )

      post_start_command = optional(string)
      pre_stop_command = optional(string)

      volumes = optional(
        list(
          object({
            uri = string
            path = string
          })
        ),
        [],
      )

      liveness_probe = optional(
        object({
          exec = optional(
            object({
              command = list(string)
            })
          )
          http_get = optional(
            object({
              path = optional(string)
              port = optional(number)
              scheme = optional(string)
              http_headers = optional(map(string))
            })
          )
          tcp_socket = optional(
            object({
              port = optional(number)
            })
          )
          grpc = optional(
            object({
              port = optional(number)
            })
          )
          failure_threshold = optional(number)
          initial_delay_seconds = optional(number)
          period_seconds = optional(number)
          success_threshold = optional(number)
          timeout_seconds = optional(number)
        })
      )

      readiness_probe = optional(
        object({
          exec = optional(
            object({
              command = list(string)
            })
          )
          http_get = optional(
            object({
              path = optional(string)
              port = optional(number)
              scheme = optional(string)
              http_headers = optional(map(string))
            })
          )
          tcp_socket = optional(
            object({
              port = optional(number)
            })
          )
          grpc = optional(
            object({
              port = optional(number)
            })
          )
          failure_threshold = optional(number)
          initial_delay_seconds = optional(number)
          period_seconds = optional(number)
          success_threshold = optional(number)
          timeout_seconds = optional(number)
        })
      )
    })
  )
}

variable "type" {
  type = string
}

variable "gvc" {
  type = string
}

variable "name" {
  type = string
}

variable "description" {
  type = string
  default = null
}

variable "tags" {
  type = map(string)
  default = {}
}

variable "identity" {
  type = object({
    self_link = string
  })
  default = null
}

variable "support_dynamic_tags" {
  type = bool
  default = false
}

variable "options" {
  type = object({
    autoscaling = optional(
      object({
        metric = optional(string)
        metric_percentile = optional(string)
        target = optional(number)
        max_scale = optional(number)
        min_scale = optional(number)
        scale_to_zero_delay = optional(number)
        max_concurrency = optional(number)
      })
    )
    capacity_ai = optional(bool, true)
    debug = optional(bool, false)
    suspend = optional(bool, false)
    timeout_seconds = optional(number, 5)
  })
  default = null
}

variable "local_options" {
  type = object({
    autoscaling = optional(
      object({
        metric = optional(string)
        metric_percentile = optional(string)
        target = optional(number)
        max_scale = optional(number)
        min_scale = optional(number)
        scale_to_zero_delay = optional(number)
        max_concurrency = optional(number)
      })
    )
    location = string
    capacity_ai = optional(bool, true)
    debug = optional(bool, false)
    suspend = optional(bool, false)
    timeout_seconds = optional(number, 5)
  })
  default = null
}

variable "rollout_options" {
  type = object({
    min_ready_seconds = optional(number)
    max_unavailable_replicas = optional(string)
    max_surge_replicas = optional(string)
    scaling_policy = optional(string, "OrderedReady")
  })
  default = null
}

variable "security_options" {
  type = object({
    filesystem_group_id = optional(number)
  })
  default = null
}

variable "firewall_spec" {
  type = object({
    external = optional(
      object({
        inbound_allow_cidr = optional(list(string))
        outbound_allow_hostname = optional(list(string))
        outbound_allow_cidr = optional(list(string))
        outbound_allow_port = optional(
          list(
            object({
              protocol = optional(string, "tcp")
              number = number
            })
          ),
          []
        )
      })
    )
    internal = optional(
      object({
        inbound_allow_type = optional(string)
        inbound_allow_workload = optional(list(string))
      }),
    ),
  })
  default = null
}

variable "load_balancer" {
  type = object({
    direct = optional(
      object({
        enabled = number
        port = optional(
          list(
            object({
              external_port = number
              protocol = string
              scheme = optional(string)
              container_port = optional(number)
            })
          ),
          []
        )
      })
    )
    geo_location = optional(
      object({
        enabled = optional(bool)
        headers = optional(
          object({
            asn = optional(string)
            city = optional(string)
            country = optional(string)
            region = optional(string)
          })
        )
      })
    )
  })
  default = null
}

variable "job" {
  type = object({
    schedule = string
    concurrency_policy = optional(string, "Forbid")
    history_limit = optional(number, 5)
    restart_policy = optional(string, "Never")
    active_deadline_seconds = optional(number)
  })
  default = null
}
