# Heroku to Control Plane `cpl` CLI

<meta name="author" content="Justin Gordon and Sergey Tarasov">
<meta name="description" content="Instructions on how to migrate from Heroku to Control Plane and a CLI called cpl to make it easier.">
<meta name="copyright" content="ShakaCode, 2023">
<meta name="keywords" content="Control Plane, Heroku, Kubernetes, K8, Infrastructure">
<meta name="google-site-verification" content="dIV4nMplcYl6YOKOaZMqgvdKXhLJ4cdYY6pS6e_YrPU" />

_A gem that provides **Heroku Flow** functionality on Control Plane, including docs for migrating from [Heroku](https://heroku.com) to [Control Plane](https://controlplane.com/shakacode)._

[![RSpec](https://github.com/shakacode/heroku-to-control-plane/actions/workflows/rspec.yml/badge.svg)](https://github.com/shakacode/heroku-to-control-plane/actions/workflows/rspec.yml)
[![Rubocop](https://github.com/shakacode/heroku-to-control-plane/actions/workflows/rubocop.yml/badge.svg)](https://github.com/shakacode/heroku-to-control-plane/actions/workflows/rubocop.yml)

[![Gem](https://badge.fury.io/rb/cpl.svg)](https://badge.fury.io/rb/cpl)

This playbook shows how to move "Heroku apps" to "Control Plane workloads" via an open-source `cpl` CLI on top of
Control Plane's `cpln` CLI.

Heroku provides a UX and CLI that enables easy publishing of Ruby on Rails and other apps. This ease of use comes via
many "Heroku" abstractions and naming conventions.

Control Plane, on the other hand, gives you access to raw cloud computing power. However, you need to know precisely how
to use it.

To simplify migration to and usage of Control Plane for Heroku users, this repository provides a **concept mapping** and
a **helper CLI** based on templates to save lots of day-to-day typing (and human errors).

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
12. [Mapping of Heroku Commands to `cpl` and `cpln`](#mapping-of-heroku-commands-to-cpl-and-cpln)
13. [Examples](#examples)
14. [Migrating Postgres Database from Heroku Infrastructure](/docs/postgres.md)
15. [Migrating Redis Database from Heroku Infrastructure](/docs/redis.md)
16. [Tips](/docs/tips.md)

## Key Features

- A `cpl` command to complement the default Control Plane `cpln` command with "Heroku style scripting." The Ruby source
  can serve as inspiration for your own scripts.
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
| ---------------- | ------------------------------------------- |
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

## Installation

1. Ensure your [Control Plane](https://controlplane.com/shakacode) account is set up. Set up an `organization` `<your-org>` for testing in that account and modify the value for `aliases.common.cpln_org` in `.controlplane/controlplane.yml`, or you can also set it with the `CPLN_ORG` environment variable. If you need an organization, please [contact Shakacode](mailto:controlplane@shakacode.com).

2. Install [Node.js](https://nodejs.org/en) (required for Control Plane CLI).

3. Install [Ruby](https://www.ruby-lang.org/en/) (required for these helpers).

4. Install Control Plane CLI, and configure access ([docs here](https://docs.controlplane.com/quickstart/quick-start-3-cli#getting-started-with-the-cli)).

```sh
# Install CLI
npm install -g @controlplane/cli

# Configure access
cpln login

# Update CLI
npm update -g @controlplane/cli
```

5. Run `cpln image docker-login --org <your-org>` to ensure that you have access to the Control Plane Docker registry.

6. Install Heroku to Control Plane `cpl` CLI, either as a [Ruby gem](https://rubygems.org/gems/cpl) or a local clone.
   For information on the latter, see [CONTRIBUTING.md](CONTRIBUTING.md). You may also install `cpl` in your project's Gemfile.

7. You can use [this Dockerfile](https://github.com/shakacode/react-webpack-rails-tutorial/blob/master/.controlplane/Dockerfile) as an example for your project. Ensure that you have Docker running.

**Note:** Do not confuse the `cpl` CLI with the `cpln` CLI. The `cpl` CLI is the Heroku to Control Plane playbook CLI.
The `cpln` CLI is the Control Plane CLI.

## Steps to Migrate

Click [here](/docs/migrating.md) to see the steps to migrate.

## Configuration Files

The `cpl` gem is based on several configuration files within a `/.controlplane` top-level directory in your project.

```
.controlplane/
├─ templates/
│  ├─ gvc.yml
│  ├─ postgres.yml
│  ├─ rails.yml
├─ controlplane.yml
├─ Dockerfile
├─ entrypoint.sh
```

1. `controlplane.yml` describes the overall application. Be sure to have `<your-org>` as the value for `aliases.common.cpln_org`, or set it with the `CPLN_ORG` environment variable.
2. `Dockerfile` builds the production application. `entrypoint.sh` is an _example_ entrypoint script for the production application, referenced in your Dockerfile.
3. `templates` directory contains the templates for the various workloads, such as `rails.yml` and `postgres.yml`.
4. `templates/gvc.yml` defines your project's GVC (like a Heroku app). More importantly, it contains ENV values for the app.
5. `templates/rails.yml` defines your Rails workload. It may inherit ENV values from the parent GVC, which is populated from the `templates/gvc.yml`. This file also configures scaling, sizing, firewalls, and other workload-specific values.
6. For other workloads (like lines in a Heroku `Procfile`), you create additional template files. For example, you can base a `templates/sidekiq.yml` on the `templates/rails.yml` file.
7. You can have other files in the `templates` directory, such as `redis.yml` and `postgres.yml`, which could setup Redis and Postgres for a testing application.

Here's a complete example of all supported config keys explained for the `controlplane.yml` file:

### `controlplane.yml`

```yaml
# Keys beginning with "cpln_" correspond to your settings in Control Plane.

aliases:
  common: &common
    # Organization name for staging (customize to your needs).
    # Production apps will use a different organization, specified below, for security.
    cpln_org: my-org-staging

    # Example apps use only one location. Control Plane offers the ability to use multiple locations.
    default_location: aws-us-east-2

    # Allows running the command `cpl setup-app`
    # instead of `cpl apply-template gvc redis postgres memcached rails sidekiq`.
    setup:
      - gvc
      - redis
      - postgres
      - memcached
      - rails
      - sidekiq

    # Configure the workload name used as a template for one-off scripts, like a Heroku one-off dyno.
    one_off_workload: rails

    # Workloads that are for the application itself and are using application Docker images.
    app_workloads:
      - rails
      - sidekiq

    # Additional "service type" workloads, using non-application Docker images.
    additional_workloads:
      - redis
      - postgres
      - memcached

    # Configure the workload name used when maintenance mode is on (defaults to "maintenance").
    maintenance_workload: maintenance

    # Fixes the remote terminal size to match the local terminal size
    # when running the commands `cpl run` or `cpl run:detached`.
    fix_terminal_size: true

    # Apps with a deployed image created before this amount of days will be listed for deletion
    # when running the command `cpl cleanup-stale-apps`.
    stale_app_image_deployed_days: 5

    # Images that exceed this quantity will be listed for deletion
    # when running the command `cpl cleanup-images`.
    image_retention_max_qty: 20

    # Images created before this amount of days will be listed for deletion
    # when running the command `cpl cleanup-images` (`image_retention_max_qty` takes precedence).
    image_retention_days: 5

    # Run workloads created before this amount of days will be listed for deletion
    # when running the command `cpl run:cleanup`.
    stale_run_workload_created_days: 2

apps:
  my-app-staging:
    # Use the values from the common section above.
    <<: *common

  my-app-review:
    <<: *common

    # If `match_if_app_name_starts_with` is `true`, then use this config for app names starting with this name,
    # e.g., "my-app-review-pr123", "my-app-review-anything-goes", etc.
    match_if_app_name_starts_with: true

  my-app-production:
    <<: *common

    # Use a different organization for production.
    cpln_org: my-org-production

    # Allows running the command `cpl promote-app-from-upstream -a my-app-production`
    # to promote the staging app to production.
    upstream: my-app-staging

    # Used by the command `cpl promote-app-from-upstream` to run a release script before deploying.
    # This is relative to the `.controlplane/` directory.
    release_script: release_script

  my-app-other:
    <<: *common

    # You can specify a different `Dockerfile` relative to the `.controlplane/` directory (defaults to "Dockerfile").
    dockerfile: ../some_other/Dockerfile
```

## Workflow

For a live example, see the [react-webpack-rails-tutorial](https://github.com/shakacode/react-webpack-rails-tutorial/blob/master/.controlplane/readme.md) repository.

This example should closely match the below example.

Suppose your app is called `tutorial-app`. You can run the following commands.

### Setup Commands

```sh
# Provision all infrastructure on Control Plane.
# `tutorial-app` will be created per definition in .controlplane/controlplane.yml.
cpl apply-template gvc postgres redis rails daily-task -a tutorial-app

# Build and push the Docker image to the Control Plane repository.
# Note, it may take many minutes. Be patient.
# Check for error messages, such as forgetting to run `cpln image docker-login --org <your-org>`.
cpl build-image -a tutorial-app

# Promote the image to the app after running the `cpl build-image` command.
# Note, the UX of the images may not show the image for up to 5 minutes. However, it's ready.
cpl deploy-image -a tutorial-app

# See how the app is starting up.
cpl logs -a tutorial-app

# Open the app in browser (once it has started up).
cpl open -a tutorial-app
```

### Promoting Code Updates

After committing code, you will update your deployment of `tutorial-app` with the following commands:

```sh
# Build and push a new image with sequential image tagging, e.g. 'tutorial-app:1', then 'tutorial-app:2', etc.
cpl build-image -a tutorial-app

# Run database migrations (or other release tasks) with the latest image,
# while the app is still running on the previous image.
# This is analogous to the release phase.
cpl run:detached rails db:migrate -a tutorial-app --image latest

# Pomote the latest image to the app.
cpl deploy-image -a tutorial-app
```

If you needed to push a new image with a specific commit SHA, you can run the following command:

```sh
# Build and push with sequential image tagging and commit SHA, e.g. 'tutorial-app:123_ABCD', etc.
cpl build-image -a tutorial-app --commit ABCD
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

In `templates/gvc.yml`:

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

Control Plane supports scheduled jobs via [cron workloads](https://docs.controlplane.com/reference/workload#cron).

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

A complete example can be found at [templates/daily-task.yml](templates/daily-task.yml), optimized for Control Plane and
suitable for development purposes.

You can create the cron workload by adding the template for it to the `.controlplane/templates/` directory and running
`cpl apply-template my-template -a my-app`, where `my-template` is the name of the template file (e.g., `my-template.yml`).

Then to view the logs of the cron workload, you can run `cpl logs -a my-app -w my-template`.

## CLI Commands Reference

Click [here](/docs/commands.md) to see the commands.

You can also run the following command:

```sh
cpl --help
```

## Mapping of Heroku Commands to `cpl` and `cpln`

| Heroku Command                                                                                                 | `cpl` or `cpln`                 |
| -------------------------------------------------------------------------------------------------------------- | ------------------------------- |
| [heroku ps](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-ps-type-type)                     | `cpl ps`                        |
| [heroku config](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-config)                       | ?                               |
| [heroku maintenance](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-maintenance)             | `cpl maintenance`               |
| [heroku logs](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-logs)                           | `cpl logs`                      |
| [heroku pg](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-pg-database)                      | ?                               |
| [heroku pipelines:promote](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-pipelines-promote) | `cpl promote-app-from-upstream` |
| [heroku psql](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-psql-database)                  | ?                               |
| [heroku redis](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-redis-database)                | ?                               |
| [heroku releases](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-releases)                   | ?                               |

## Examples

- See the `examples/` and `templates/` directories of this repository.
- See the `.controlplane/` directory of this live example:
  [react-webpack-rails-tutorial](https://github.com/shakacode/react-webpack-rails-tutorial/tree/master/.controlplane)
