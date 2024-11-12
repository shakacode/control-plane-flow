module "rails-app" {
  source = "../workload"
  type = "standard"
  name = "rails-app"
  gvc = cpln_gvc.rails-app-production.name
  containers = {
    rails: {
      image: "org-name/rails-app:latest",
      cpu: "300m",
      memory: "512Mi",
      inherit_env: true,
      envs: local.rails_envs,
      ports: [
        {
          number: 3000,
          protocol: "http"
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
