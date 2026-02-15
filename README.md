# The power of Kubernetes with the ease of Heroku!

<meta name="author" content="Justin Gordon and Sergey Tarasov" />
<meta name="description" content="Instructions on how to migrate from Heroku to Control Plane and a CLI called cpflow to make it easier." />
<meta name="copyright" content="ShakaCode, 2023" />
<meta name="keywords" content="Control Plane, Heroku, Kubernetes, K8, Infrastructure" />
<meta name="google-site-verification" content="dIV4nMplcYl6YOKOaZMqgvdKXhLJ4cdYY6pS6e_YrPU" />

[![RSpec](https://github.com/shakacode/control-plane-flow/actions/workflows/rspec.yml/badge.svg)](https://github.com/shakacode/control-plane-flow/actions/workflows/rspec.yml)
[![Rubocop](https://github.com/shakacode/control-plane-flow/actions/workflows/rubocop.yml/badge.svg)](https://github.com/shakacode/control-plane-flow/actions/workflows/rubocop.yml)

[![Gem](https://badge.fury.io/rb/cpflow.svg)](https://badge.fury.io/rb/cpflow)


Leverage the power of Kubernetes with the ease of Heroku! The `cpflow` gem enables simple CI configuration for Heroku-style "review apps," staging deployments, and seamless promotion from staging to production. This is similar to the the [Heroku Flow](https://www.heroku.com/flow) deployment model.

Follow the "convention over configuration" philosophy to streamline your deployment workflows and reduce complexity.

----

_If you need a free demo account for Control Plane (no CC required), you can contact [Justin Gordon, CEO of ShakaCode](mailto:justin@shakacode.com)._

---

Be sure to see the [demo app](https://github.com/shakacode/react-webpack-rails-tutorial/tree/master/.controlplane), which includes simple YAML configurations and setup for `cpflow`.

Also, check [how the `cpflow` gem (this project) is used in the Github actions](https://github.com/shakacode/react-webpack-rails-tutorial/blob/master/.github/actions/deploy-to-control-plane/action.yml).
Here is a brief [video overview](https://www.youtube.com/watch?v=llaQoAV_6Iw).

---

This playbook shows how to move "Heroku apps" to "Control Plane workloads" via an open-source `cpflow` CLI on top of
Control Plane's `cpln` CLI.

Heroku provides a UX and CLI that enables easy publishing of Ruby on Rails and other apps. This ease of use comes via
many "Heroku" abstractions and naming conventions.

Control Plane provides access to raw cloud computing power but lacks the simple abstractions of Heroku. The `cpflow` CLI bridges this gap, delivering a streamlined and familiar experience for developers.

While this repository simplifies migration from Heroku, the `cpflow` CLI is versatile and can be used for any application. This document contains **concept mapping** and **helper CLI** approach to streamline deployment workflows and minimize manual effort.

Additionally, the documentation includes numerous examples and practical tips for teams transitioning from Heroku to Kubernetes, helping them make the most of Control Plane's advanced features.

1. [Key Features](#key-features)
2. [Concept Mapping](#concept-mapping)
3. [Installation](#installation)
4. [Steps to Migrate](#steps-to-migrate)
5. [Configuration Files](#configuration-files)
6. [Workflow](#workflow)
7. [Environment](#environment)
8. [Database](#database)
9. [In-memory Databases](#in-memory-databases)
10. [Scheduled Jobs](#scheduled-jobs)
11. [CLI Commands Reference](#cli-commands-reference)
12. [Mapping of Heroku Commands to `cpflow` and `cpln`](#mapping-of-heroku-commands-to-cpflow-and-cpln)
13. [Examples](#examples)
14. [Migrating Postgres Database from Heroku Infrastructure](https://www.shakacode.com/control-plane-flow/docs/postgres/)
15. [Migrating Redis Database from Heroku Infrastructure](https://www.shakacode.com/control-plane-flow/docs/redis/)
16. [Tips](https://www.shakacode.com/control-plane-flow/docs/tips/)

## Key Features

- The `cpflow` CLI complements the Control Plane `cpln` CLI, enabling "Heroku-style scripting" for review apps, staging, and production environments.
- Extensive Heroku-to-Control Plane migration examples included in the documentation.
- Convention-driven configuration to simplify workflows and reduce custom scripting requirements.
- Easy to understand Heroku to Control Plane conventions in setup and naming.
- **Safe, production-ready** equivalents of `heroku run` and `heroku run:detached` for Control Plane.
- Automatic sequential release tagging for Docker images.
- A project-aware CLI that enables working on multiple projects.

## Concept Mapping

On Heroku, everything runs as an app, which means an entity that:

- runs code from a Git repository.
- runs several process types, as defined in the `Procfile`.
- has dynos, which are Linux containers that run these process types.
- has add-ons, including the database and other services.
- has common environment variables.

On Control Plane, we can map a Heroku app to a GVC (Global Virtual Cloud). Such a cloud consists of workloads, which can
be anything that can run as a container.

| Heroku           | Control Plane                               |
|------------------|---------------------------------------------|
| _app_            | _GVC_ (Global Virtual Cloud)                |
| _dyno_           | _workload_                                  |
| _add-on_         | either a _workload_ or an external resource |
| _review app_     | _GVC (app)_ in staging _organization_       |
| _staging env_    | _GVC (app)_ in staging _organization_       |
| _production env_ | _GVC (app)_ in production _organization_    |

On Heroku, dyno types are specified in the `Procfile` and configured via the CLI/UI; add-ons are configured only via the
CLI/UI.

On Control Plane, workloads are created either by _templates_ (preferred way) or via the CLI/UI.

For the typical Rails app, this means:

| Function        | Examples             | On Heroku     | On Control Plane                                                                                                  |
| --------------- | -------------------- | ------------- | ----------------------------------------------------------------------------------------------------------------- |
| web traffic     | `rails`, `sinatra`   | `web` dyno    | workload with app image                                                                                           |
| background jobs | `sidekiq`, `resque`  | `worker` dyno | workload with app image                                                                                           |
| db              | `postgres`, `mysql`  | add-on        | external provider or can be set up for development/testing with Docker image (lacks persistence between restarts) |
| in-memory db    | `redis`, `memcached` | add-on        | external provider or can be set up for development/testing with Docker image (lacks persistence between restarts) |
| others          | `mailtrap`           | add-on        | external provider or can be set up for development/testing with Docker image (lacks persistence between restarts) |

## Migration Strategy
See this doc for [detailed migration steps](./docs/migrating-heroku-to-control-plane.md) from Heroku to Control Plane. Even if you are coming from a platform other than Heroku, you can still benefit from the migration steps.

## System Prerequisites

_Note, if you want to use Terraform with cpflow, you will start the same way below._

1. Ensure your [Control Plane](https://shakacode.controlplane.com/) account is set up. Set up an `organization` `<your-org>` for testing in that account and modify the value for `aliases.common.cpln_org` in `.controlplane/controlplane.yml`, or you can also set it with the `CPLN_ORG` environment variable. If you need an organization, please [contact Shakacode](mailto:controlplane@shakacode.com).

2. Install [Node.js](https://nodejs.org/en) (required for Control Plane CLI).

3. Install [Ruby](https://www.ruby-lang.org/en/) (required for these helpers).

4. Install Control Plane CLI, and configure access ([docs here](https://shakadocs.controlplane.com/quickstart/quick-start-3-cli#getting-started-with-the-cli)).

```sh
# Install CLI
npm install -g @controlplane/cli

# Configure access
cpln login

# Update CLI
npm update -g @controlplane/cli
```

5. Run `cpln image docker-login --org <your-org>` to ensure that you have access to the Control Plane Docker registry.

6. Install Control Plane Flow `cpflow` CLI as a [Ruby gem](https://rubygems.org/gems/cpflow): `gem install cpflow`. If you want to use `cpflow` from Rake tasks in a Rails project, use `Bundler.with_unbundled_env { `cpflow help` } or else you'll get an error that `cpflow` cannot be found. While you can add `cpflow` to your Gemfile, it's not recommended because it might trigger conflicts with other gems.

7. You will need a production-ready Dockerfile. If you're using Rails, consider the default one that ships with Rails 8. You can use [this Dockerfile](https://github.com/shakacode/rails-v8-kamal-v2-terraform-gcp-tutorial/blob/master/Dockerfile) as an example for your project. Ensure that you have Docker running.

**Note:** Do not confuse the `cpflow` CLI with the `cpln` CLI. The `cpflow` CLI is the Control Plane Flow playbook CLI.
The `cpln` CLI is the Control Plane CLI.

## Configuration Files

The `cpflow` gem is based on several configuration files within a `/.controlplane` top-level directory in your project.

```
.controlplane/
├─ templates/
│  ├─ app.yml
│  ├─ postgres.yml
│  ├─ rails.yml
├─ controlplane.yml
├─ Dockerfile
├─ entrypoint.sh
```

1. `controlplane.yml` describes the overall application. Be sure to have `<your-org>` as the value for `aliases.common.cpln_org`, or set it with the `CPLN_ORG` environment variable.
2. `Dockerfile` builds the production application. `entrypoint.sh` is an _example_ entrypoint script for the production application, referenced in your Dockerfile.
3. `templates` directory contains the templates for the various workloads, such as `rails.yml` and `postgres.yml`.
4. `templates/app.yml` defines your project's GVC (like a Heroku app). More importantly, it contains ENV values for the app.
5. `templates/rails.yml` defines your Rails workload. It may inherit ENV values from the parent GVC, which is populated from the `templates/app.yml`. This file also configures scaling, sizing, firewalls, and other workload-specific values.
6. For other workloads (like lines in a Heroku `Procfile`), you create additional template files. For example, you can base a `templates/sidekiq.yml` on the `templates/rails.yml` file.
7. You can have other files in the `templates` directory, such as `redis.yml` and `postgres.yml`, which could setup Redis and Postgres for a testing application.

Here's a complete example of all supported config keys explained for the `controlplane.yml` file:

### `controlplane.yml`

```yaml
# Keys beginning with "cpln_" correspond to your settings in Control Plane.

# Global settings that apply to `cpflow` usage.
# You can opt out of allowing the use of CPLN_ORG and CPLN_APP env vars
# to avoid any accidents with the wrong org / app.
allow_org_override_by_env: true
allow_app_override_by_env: true

aliases:
  common: &common
    # Organization for staging and QA apps is typically set as an alias.
    # Production apps will use a different organization, specified in `apps`, for security.
    # Change this value to your organization name
    # or set the CPLN_ORG env var and it will override this for all `cpflow` commands
    # (provided that `allow_org_override_by_env` is set to `true`).
    cpln_org: my-org-staging

    # Control Plane offers the ability to use multiple locations.
    # default_location is used for commands that require a location
    # including `ps`, `run`, `apply-template`.
    # This can be overridden with option --location=<location> and
    # CPLN_LOCATION environment variable.
    default_location: aws-us-east-2

    # Allows running the command `cpflow setup-app`
    # instead of `cpflow apply-template app redis postgres memcached rails sidekiq`.
    #
    # Note:
    # 1. These names correspond to files in the `./controlplane/templates` directory.
    # 2. Each file can contain many objects, such as in the case of templates that create a resource, like `postgres`.
    # 3. While the naming often corresponds to a workload or other object name, the naming is arbitrary. 
    #    Naming does not need to match anything other than the file name without the `.yml` extension.
    setup_app_templates:
      - app
      - redis
      - postgres
      - memcached
      - rails
      - sidekiq

    # Skips secrets setup when running `cpflow setup-app`.
    skip_secrets_setup: true

    # Only needed if using a custom secrets name.
    # The default is '{APP_PREFIX}-secrets'. For example:
    # - for an app 'my-app-staging' with `match_if_app_name_starts_with` set to `false`,
    #   it would be 'my-app-staging-secrets'
    # - for an app 'my-app-review-1234' with `match_if_app_name_starts_with` set to `true`,
    #   it would be 'my-app-review-secrets'
    secrets_name: my-secrets

    # Only needed if using a custom secrets policy name.
    # The default is '{APP_SECRETS}-policy'. For example:
    # - for an app 'my-app-staging' with `match_if_app_name_starts_with` set to `false`,
    #   it would be 'my-app-staging-secrets-policy'
    # - for an app 'my-app-review-1234' with `match_if_app_name_starts_with` set to `true`,
    #   it would be 'my-app-review-secrets-policy'
    secrets_policy_name: my-secrets-policy

    # Configure the workload name used as a template for one-off scripts, like a Heroku one-off dyno.
    one_off_workload: rails

    # Workloads that are for the application itself and are using application Docker images.
    # These are updated with the new image when running the `deploy-image` command,
    # and are also used by the `info` and `ps:` commands in order to get all of the defined workloads.
    # On the other hand, if you have a workload for Redis, that would NOT use the application Docker image
    # and not be listed here.
    app_workloads:
      - rails
      - sidekiq

    # Additional "service type" workloads, using non-application Docker images.
    # These are only used by the `info` and `ps:` commands in order to get all of the defined workloads.
    additional_workloads:
      - redis
      - postgres
      - memcached

    # Configure the workload name used when maintenance mode is on (defaults to "maintenance").
    maintenance_workload: maintenance

    # Fixes the remote terminal size to match the local terminal size
    # when running `cpflow run`.
    fix_terminal_size: true

    # Sets a default CPU size for `cpflow run` jobs (can be overridden per job through `--cpu`).
    # If not specified, defaults to "1" (1 core).
    runner_job_default_cpu: "2"

    # Sets a default memory size for `cpflow run` jobs (can be overridden per job through `--memory`).
    # If not specified, defaults to "2Gi" (2 gibibytes).
    runner_job_default_memory: "4Gi"

    # Sets the maximum number of seconds that `cpflow run` jobs can execute before being stopped.
    # If not specified, defaults to 21600 (6 hours).
    runner_job_timeout: 1000

    # Apps with a deployed image created before this amount of days will be listed for deletion
    # when running the command `cpflow cleanup-stale-apps`.
    stale_app_image_deployed_days: 5

    # Images that exceed this quantity will be listed for deletion
    # when running the command `cpflow cleanup-images`.
    image_retention_max_qty: 20

    # Images created before this amount of days will be listed for deletion
    # when running the command `cpflow cleanup-images` (`image_retention_max_qty` takes precedence).
    image_retention_days: 5

apps:
  my-app-staging:
    # Use the values from the common section above.
    <<: *common

  my-app-review:
    <<: *common

    # If `match_if_app_name_starts_with` is `true`, then use this config for app names starting with this name,
    # e.g., "my-app-review-pr123", "my-app-review-anything-goes", etc.
    match_if_app_name_starts_with: true

    # Hooks can be either a script path that exists in the app image or a command.
    # They're run in the context of `cpflow run` with the latest image.
    hooks:
      # Used by the command `cpflow setup-app` to run a hook after creating the app.
      post_creation: bundle exec rake db:prepare

      # Used by the command `cpflow delete` to run a hook before deleting the app.
      pre_deletion: bundle exec rake db:drop

  my-app-production:
    <<: *common

    # You can also opt out of allowing the use of CPLN_ORG and CPLN_APP env vars per app.
    # It's recommended to leave this off for production, to avoid any accidents.
    allow_org_override_by_env: false
    allow_app_override_by_env: false

    # Use a different organization for production.
    cpln_org: my-org-production

    # Allows running the command `cpflow promote-app-from-upstream -a my-app-production`
    # to promote the staging app to production.
    upstream: my-app-staging

    # Used by the command `cpflow promote-app-from-upstream` to run a release script before deploying.
    # This is relative to the `.controlplane/` directory.
    release_script: release_script

    # default_domain is used for commands that require a domain
    # including `maintenance`, `maintenance:on`, `maintenance:off`.
    default_domain: domain.com

  my-app-other:
    <<: *common

    # You can specify a different `Dockerfile` relative to the `.controlplane/` directory (defaults to "Dockerfile").
    dockerfile: ../some_other/Dockerfile
```

## Workflow

For a live example, see the [react-webpack-rails-tutorial](https://github.com/shakacode/react-webpack-rails-tutorial/blob/master/.controlplane/readme.md) repository.

You can use this repository as a reference for setting up your own project.

This example should closely match the below example.

Suppose your app is called `tutorial-app`. You can run the following commands.

### Setup Commands

```sh
# Provision all infrastructure on Control Plane.
# `tutorial-app` will be created per definition in .controlplane/controlplane.yml.
cpflow apply-template app postgres redis rails daily-task -a tutorial-app

# Build and push the Docker image to the Control Plane repository.
# Note, it may take many minutes. Be patient.
# Check for error messages, such as forgetting to run `cpln image docker-login --org <your-org>`.
cpflow build-image -a tutorial-app

# Promote the image to the app after running the `cpflow build-image` command.
# Note, the UX of the images may not show the image for up to 5 minutes. However, it's ready.
cpflow deploy-image -a tutorial-app

# See how the app is starting up.
cpflow logs -a tutorial-app

# Open the app in browser (once it has started up).
cpflow open -a tutorial-app
```

### Promoting Code Updates

After committing code, you will update your deployment of `tutorial-app` with the following commands:

```sh
# Build and push a new image with sequential image tagging, e.g. 'tutorial-app:1', then 'tutorial-app:2', etc.
cpflow build-image -a tutorial-app

# Run database migrations (or other release tasks) with the latest image,
# while the app is still running on the previous image.
# This is analogous to the release phase.
cpflow run -a tutorial-app --image latest -- rails db:migrate

# Pomote the latest image to the app.
cpflow deploy-image -a tutorial-app
```

If you needed to push a new image with a specific commit SHA, you can run the following command:

```sh
# Build and push with sequential image tagging and commit SHA, e.g. 'tutorial-app:123_ABCD', etc.
cpflow build-image -a tutorial-app --commit ABCD
```

### Real World

Most companies will configure their CI system to handle the above steps. Please [contact Shakacode](mailto:controlplane@shakacode.com) for examples of how to do this.

You can also join our [**Slack channel**](https://reactrails.slack.com/join/shared_invite/enQtNjY3NTczMjczNzYxLTlmYjdiZmY3MTVlMzU2YWE0OWM0MzNiZDI0MzdkZGFiZTFkYTFkOGVjODBmOWEyYWQ3MzA2NGE1YWJjNmVlMGE) for ShakaCode open source projects.

## Environment

There are two main places where we can set up environment variables in Control Plane:

- **In `workload/container/env`** - those are container-specific and must be set up individually for each container.

- **In `gvc/env`** - this is a "common" place to keep env vars which we can share among different workloads. Those
  common variables are not visible by default, and we should explicitly enable them via the `inheritEnv` property.

Generally, `gvc/env` vars are useful for "app" types of workloads, e.g., `rails`, `sidekiq`, as they can easily share
common configs (the same way as on a Heroku app). They are not needed for non-app workloads, e.g., `redis`, `memcached`.

It is ok to keep most of the environment variables for non-production environments in the app templates as, in general,
they are not secret and can be committed to the repository.

It is also possible to set up a Secret store (of type `Dictionary`), which we can reference as, e.g.,
`cpln://secret/MY_SECRET_STORE_NAME/MY_SECRET_VAR_NAME`. In such a case, we must set up an app Identity and proper
Policy to access the secret.

In `templates/app.yml`:

```yaml
spec:
  env:
    - name: MY_GLOBAL_VAR
      value: "value"
    - name: MY_SECRET_GLOBAL_VAR
      value: "cpln://secret/MY_SECRET_STORE_NAME/MY_SECRET_GLOBAL_VAR"
```

In `templates/rails.yml`:

```yaml
spec:
  containers:
    - name: rails
      env:
        - name: MY_LOCAL_VAR
          value: "value"
        - name: MY_SECRET_LOCAL_VAR
          value: "cpln://secret/MY_SECRET_STORE_NAME/MY_SECRET_LOCAL_VAR"
      inheritEnv: true # To enable global env inheritance.
```

## Database

There are several options for a database setup on Control Plane:

- **Heroku Postgres**. It is the least recommended but simplest. We only need to provision the Postgres add-on on Heroku
  and copy its `XXXXXX_URL` connection string. This is good for quick testing but unsuitable for the long term.

- **Control Plane container**. We can set it up as a workload using one of the default
  [Docker Hub](https://hub.docker.com/) images. However, such a setup lacks persistence between container restarts. We
  can use this only for an example or test app where the database doesn't keep any serious data and where such data is
  restorable.

- Any other cloud provider for Postgres, e.g., Amazon's RDS can be a quick go-to. Here are
  [instructions for setting up a free tier of RDS](https://aws.amazon.com/premiumsupport/knowledge-center/free-tier-rds-launch/).

**Tip:** If you are using RDS for development/testing purposes, you might consider running such a database publicly
accessible (Heroku actually does that for all of its Postgres databases unless they are within private spaces). Then we
can connect to such a database from everywhere with only the correct username/password.

By default, we have structured our templates to accomplish this with only a single free tier or low tier AWS RDS
instance that can serve all your development/testing needs for small/medium applications, e.g., as follows:

```sh
aws-rds-single-pg-instance
  mydb-staging
  mydb-review-111
  mydb-review-222
  mydb-review-333
```

Additionally, we provide a default `postgres` template in this repository optimized for Control Plane and suitable for
development purposes.

## In-memory Databases

E.g., Redis, Memcached.

For development purposes, it's useful to set those up as Control Plane workloads, as in most cases, they don't keep any
valuable data and can be safely restarted, which doesn't affect application performance.

For production purposes or where restarts are not an option, you should use external cloud services.

We provide default `redis` and `memcached` templates in this repository optimized for Control Plane and suitable for
development purposes.

## Scheduled Jobs

Control Plane supports scheduled jobs via [cron workloads](https://shakadocs.controlplane.com/reference/workload/types#cron).

Here's a partial example of a template for a cron workload, using the app image:

```yaml
kind: workload
name: daily-task
spec:
  type: cron
  job:
    # Run daily job at 2am.
    schedule: "0 2 * * *"
    # "Never" or "OnFailure"
    restartPolicy: Never
  containers:
    - name: daily-task
      args:
        - bundle
        - exec
        - rails
        - db:prepare
      image: "/org/APP_ORG/image/APP_IMAGE"
```

A complete example can be found at [templates/daily-task.yml](https://github.com/shakacode/control-plane-flow/blob/main/templates/daily-task.yml), optimized for Control Plane and
suitable for development purposes.

You can create the cron workload by adding the template for it to the `.controlplane/templates/` directory and running
`cpflow apply-template my-template -a my-app`, where `my-template` is the name of the template file (e.g., `my-template.yml`).

Then to view the logs of the cron workload, you can run `cpflow logs -a my-app -w my-template`.

## CLI Commands Reference

Click [here](https://www.shakacode.com/control-plane-flow/docs/commands/) to see the commands.

You can also run the following command:

```sh
cpflow --help
```

## Mapping of Heroku Commands to `cpflow` and `cpln`

| Heroku Command                                                                                                 | `cpflow` or `cpln`                 |
| -------------------------------------------------------------------------------------------------------------- | ------------------------------- |
| [heroku ps](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-ps-type-type)                     | `cpflow ps`                        |
| [heroku config](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-config)                       | ?                               |
| [heroku maintenance](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-maintenance)             | `cpflow maintenance`               |
| [heroku logs](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-logs)                           | `cpflow logs`                      |
| [heroku pg](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-pg-database)                      | ?                               |
| [heroku pipelines:promote](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-pipelines-promote) | `cpflow promote-app-from-upstream` |
| [heroku psql](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-psql-database)                  | ?                               |
| [heroku redis](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-redis-database)                | ?                               |
| [heroku releases](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-releases)                   | ?                               |

## Examples

- See this repository's `examples/` and `templates/` directories.
- See the `.controlplane/` directory of this live example:
  [react-webpack-rails-tutorial](https://github.com/shakacode/react-webpack-rails-tutorial/tree/master/.controlplane).
- See [how the `cpflow` gem is used in the Github actions](https://github.com/shakacode/react-webpack-rails-tutorial/blob/master/.github/actions/deploy-to-control-plane/action.yml).
- Here is a brief [video overview](https://www.youtube.com/watch?v=llaQoAV_6Iw).

## Resources
* If you need a free demo account for Control Plane (no CC required), you can contact [Justin Gordon, CEO of ShakaCode](mailto:justin@shakacode.com).
* [Control Plane Site](https://shakacode.controlplane.com)
* [Join our Slack to Discuss Control Plane Flow](https://reactrails.slack.com/join/shared_invite/enQtNjY3NTczMjczNzYxLTlmYjdiZmY3MTVlMzU2YWE0OWM0MzNiZDI0MzdkZGFiZTFkYTFkOGVjODBmOWEyYWQ3MzA2NGE1YWJjNmVlMGE)
