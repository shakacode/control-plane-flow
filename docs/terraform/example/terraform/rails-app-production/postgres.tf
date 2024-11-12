module "postgres" {
  source = "../workload"
  type = "standard"
  name = "postgres"
  gvc = cpln_gvc.rails-app-production.name
  containers = {
    postgres: {
      image: "postgres:latest",
      cpu: "500m",
      memory: "1Gi",
      inherit_env: true,
      envs: local.postgres_envs,
      ports: [
        {
          number: 5432,
          protocol: "tcp"
        }
      ]
    }
  }
  options = {
    autoscaling: {
      max_scale: 1
    }
    capacity_ai: false
  }
  firewall_spec = {
    external: {
      inbound_allow_cidr: [
        "0.0.0.0/0"
      ],
      outbound_allow_cidr: [
        "0.0.0.0/0"
      ]
    }
  }
}
