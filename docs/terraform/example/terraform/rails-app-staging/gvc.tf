resource "cpln_gvc" "rails-app-staging" {
  name = "rails-app-staging"
  description = "Global Virtual Cloud for Rails Application"
  locations = ["aws-us-east-2"]
  pull_secrets = [cpln_secret.rails-app-secret.name]
  env = {
    DATABASE_URL = "postgres://user:password@postgres.rails-app-staging.cpln.local:5432/rails-app-staging"
    RAILS_ENV = "production"
    RAILS_SERVE_STATIC_FILES = "true"
  }
  load_balancer {
    dedicated = true
    trusted_proxies = 0
  }
}
