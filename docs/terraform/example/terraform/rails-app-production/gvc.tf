resource "cpln_gvc" "rails-app-production" {
  name = "rails-app-production"
  description = "Global Virtual Cloud for Rails Application"
  locations = ["aws-us-east-2"]
  pull_secrets = [cpln_secret.rails-app-secret.name]
  env = {
    DATABASE_URL = "postgres://user:password@postgres.rails-app-production.cpln.local:5432/rails-app-production"
    RAILS_ENV = "production"
    RAILS_SERVE_STATIC_FILES = "true"
  }
  load_balancer {
    dedicated = true
    trusted_proxies = 0
  }
}
