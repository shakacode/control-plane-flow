resource "cpln_identity" "rails-app-identity" {
  gvc = cpln_gvc.rails-app-production.name
  name = "rails-app-identity"
  description = "Identity for Rails Application"
  tags = {
    environment = "production"
  }
}
