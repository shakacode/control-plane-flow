resource "cpln_secret" "rails-app-secret" {
  name = "rails-app-secret"
  description = "Secret for Rails Application"
  aws {
    secret_key = "SecretKeyExample"
    access_key = "AccessKeyExample"
  }
}
