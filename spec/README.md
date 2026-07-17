# Running Specs

Some specs exercise only local behavior and can run without Control Plane credentials. This verified offline smoke suite does not contact a Control Plane org:

```sh
CPLN_ORG='' bundle exec rspec \
  spec/patches \
  spec/support_specs \
  spec/core/controlplane_api_direct_spec.rb \
  spec/core/controlplane_api_spec.rb \
  spec/core/doctor_service_spec.rb \
  spec/core/github_flow_readiness/checks_spec.rb \
  spec/core/helpers_spec.rb \
  spec/core/repo_introspection_spec.rb \
  spec/core/shell_spec.rb \
  spec/rakelib/create_release_spec.rb \
  spec/command/no_command_spec.rb \
  spec/command/staging_branch_validation_spec.rb \
  spec/command/test_spec.rb \
  spec/command/update_github_actions_spec.rb \
  spec/command/version_spec.rb \
  spec/command/deploy_image_unit_spec.rb \
  spec/command/promote_app_from_upstream_unit_spec.rb
```

The spec helper still prepares the temporary dummy configuration for these runs. A spec that needs a real Control Plane org raises a clear error when it calls `dummy_test_org`; rerun that spec with `CPLN_ORG` set.

Specs that create, inspect, or delete Control Plane resources need an org with the required access:

```sh
CPLN_ORG=your-org-for-tests bundle exec rspec
```

Slow specs are a subset of the credentialed suite. Run them separately with:

```sh
CPLN_ORG=your-org-for-tests bundle exec rspec --tag slow
```
