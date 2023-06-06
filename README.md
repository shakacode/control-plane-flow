# Heroku to Control Plane `cpl` CLI

<meta name="author" content="Justin Gordon and Sergey Tarasov">
<meta name="description" content="Instructions on how to migrate from Heroku to Control Plane and a CLI called cpl to make it easier.">
<meta name="copyright" content="ShakaCode, 2023">
<meta name="keywords" content="Control Plane, Heroku, Kubernetes, K8, Infrastructure">
<meta name="google-site-verification" content="dIV4nMplcYl6YOKOaZMqgvdKXhLJ4cdYY6pS6e_YrPU" />

_A playbook for migrating from [Heroku](https://heroku.com) to [Control Plane](https://controlplane.com)_

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
4. [Example CLI Flow for Application Build/Deployment](#example-cli-flow-for-application-builddeployment)
   - [Initial Setup and Deployment](#initial-setup-and-deployment)
   - [Promoting Code Upgrades](#promoting-code-upgrades)
5. [Example Project Modifications for Control Plane](#example-project-modifications-for-control-plane)
6. [Environment](#environment)
7. [Database](#database)
8. [In-memory Databases](#in-memory-databases)
9. [Scheduled Jobs](#scheduled-jobs)
10. [CLI Commands Reference](#cli-commands-reference)
11. [Mapping of Heroku Commands to `cpl` and `cpln`](#mapping-of-heroku-commands-to-cpl-and-cpln)
12. [Examples](#examples)
13. [Migrating Postgres Database from Heroku Infrastructure](/docs/postgres.md)
14. [Migrating Redis Database from Heroku Infrastructure](/docs/redis.md)
15. [Tips](/docs/tips.md)

## Key Features

- A `cpl` command to complement the default Control Plane `cpln` command with "Heroku style scripting." The Ruby source
  can serve as inspiration for your own scripts.
- Easy to understand Heroku to Control Plane conventions in setup and naming.
- **Safe, production-ready** equivalents of `heroku run` and `heroku run:detached` for Control Plane.
- Automatic sequential release tagging for Docker images.
- A project-aware CLI which enables working on multiple projects.

## Concept Mapping

On Heroku, everything runs as an app, which means an entity that:

- runs code from a Git repo
- runs several process types, as defined in the `Procfile`
- has dynos, which are Linux containers that run these process types
- has add-ons, including the database and other services
- has common environment variables

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

| Function          | Examples             | On Heroku     | On Control Plane                                                                                                  |
| ----------------- | -------------------- | ------------- | ----------------------------------------------------------------------------------------------------------------- |
| web traffic       | `rails`, `sinatra`   | `web` dyno    | workload with app image                                                                                           |
| background jobs   | `sidekiq`, `resque`  | `worker` dyno | workload with app image                                                                                           |
| db                | `postgres`, `mysql`  | add-on        | external provider or can be set up for development/testing with Docker image (lacks persistence between restarts) |
| in-memory db      | `redis`, `memcached` | add-on        | external provider or can be set up for development/testing with Docker image (lacks persistence between restarts) |
| special something | `mailtrap`           | add-on        | external provider or can be set up for development/testing with Docker image (lacks persistence between restarts) |

## Installation

1. Install [Node.js](https://nodejs.org/en) (required for Control Plane CLI).
2. Install [Ruby](https://www.ruby-lang.org/en/) (required for these helpers).
3. Install Control Plane CLI (adds `cpln` command) and configure credentials.

```sh
npm install -g @controlplane/cli
cpln login
```

4. Install Heroku to Control Plane `cpl` CLI, either as a [Ruby gem](https://rubygems.org/gems/cpl) or a local clone.
   For information on the latter, see [CONTRIBUTING.md](CONTRIBUTING.md).

```sh
gem install cpl
```

**Note:** Do not confuse the `cpl` CLI with the `cpln` CLI. The `cpl` CLI is the Heroku to Control Plane playbook CLI.
The `cpln` CLI is the Control Plane CLI.

## Example CLI Flow for Application Build/Deployment

**Notes:**

- `my-app` is an app name defined in the `.controlplane/controlplane.yml` file, such as `ror-tutorial` in
  [this `controlplane.yml` file](https://github.com/shakacode/react-webpack-rails-tutorial/blob/master/.controlplane/controlplane.yml).
- Other files in the `.controlplane/templates` directory are used by the `cpl setup-app` and `cpl apply-template`
  commands.

### Initial Setup and Deployment

For each Git project that you want to deploy to Control Plane, copy project-specific configs to a `.controlplane`
directory at the top of your project. `cpl` will pick those up depending on which project folder tree it runs. Thus,
this automates running several projects with different configs without explicitly switching configs.

Before the initial setup, add the templates for the app to `.controlplane/controlplane.yml`, using the `setup` key, e.g.:

```yaml
my-app:
  setup:
    - gvc
    - postgres
    - redis
    - memcached
    - rails
    - sidekiq
```

Note how the templates correspond to files in the `.controlplane/templates` directory.

Then create a `Dockerfile` for your deployment. See
[this example](https://github.com/shakacode/react-webpack-rails-tutorial/blob/master/.controlplane/Dockerfile).

```sh
# Provision infrastructure (one-time-only for new apps) using templates.
cpl setup-app -a my-app

# Build and push image with auto-tagging, e.g., "my-app:1_456".
cpl build-image -a my-app --commit 456

# Prepare database.
cpl run:detached -a my-app --image latest -- rails db:prepare

# Deploy latest image.
cpl deploy-image -a my-app

# Open app in browser.
cpl open -a my-app
```

### Promoting Code Upgrades

```sh
# Build and push new image with sequential tagging, e.g., "my-app:2".
cpl build-image -a my-app

# OR
# Build and push new image with sequential tagging and commit SHA, e.g., "my-app:2_ABC".
cpl build-image -a my-app --commit ABC

# Run database migrations (or other release tasks) with latest image,
# while app is still running on previous image.
# This is analogous to the release phase.
cpl run:detached -a my-app --image latest -- rails db:migrate

# Deploy latest image.
cpl deploy-image -a my-app
```

## Example Project Modifications for Control Plane

_See this for a complete example._

To learn how to migrate an app, we recommend that you first follow along with
[this example project](https://github.com/shakacode/react-webpack-rails-tutorial).

1. Create the `.controlplane` directory at the top of your project and copy files from the `templates` directory of this
   repo to something as follows:

```sh
app_main_folder/
  .controlplane/
    Dockerfile          # Your app's Dockerfile, with some Control Plane changes.
    controlplane.yml
    entrypoint.sh       # App-specific, edit as needed.
    templates/
      gvc.yml
      memcached.yml
      postgres.yml
      rails.yml
      redis.yml
      sidekiq.yml
```

The example [`.controlplane` directory](https://github.com/shakacode/react-webpack-rails-tutorial/tree/master/.controlplane)
already contains these files.

2. Edit your `controlplane.yml` file as needed. For example, see
   [this `controlplane.yml` file](https://github.com/shakacode/react-webpack-rails-tutorial/blob/master/.controlplane/controlplane.yml).

```yaml
# Keys beginning with "cpln_" correspond to your settings in Control Plane.

aliases:
  common: &common
    # Organization name for staging (customize to your needs).
    # Production apps will use a different Control Plane organization, specified below, for security.
    cpln_org: my-org-staging

    # Example apps use only one location. Control Plane offers the ability to use multiple locations.
    # TODO -- allow specification of multiple locations
    default_location: aws-us-east-2

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

    # Configure the workload name used when maintenance mode is on (defaults to 'maintenance')
    maintenance_workload: maintenance

apps:
  my-app-staging:
    # Use the values from the common section above.
    <<: *common
  my-app-review:
    <<: *common
    # If `match_if_app_name_starts_with` == `true`, then use this config for app names starting with this name,
    # e.g., "my-app-review-pr123", "my-app-review-anything-goes", etc.
    match_if_app_name_starts_with: true
  my-app-production:
    <<: *common
    # Use a different organization for production.
    cpln_org: my-org-production
    # Allows running the command `cpl promote-app-from-upstream -a my-app-production` to promote the staging app to production.
    upstream: my-app-staging
  my-app-other:
    <<: *common
    # You can specify a different `Dockerfile` relative to the `.controlplane` directory (default is just "Dockerfile").
    dockerfile: ../some_other/Dockerfile
```

3. We recommend that you try out the commands listed in [the example](https://github.com/shakacode/react-webpack-rails-tutorial/blob/master/.controlplane/readme.md).
   These steps will guide you through:

   1. Provision the GVC and workloads
   2. Build the Docker image
   3. Run Rails migrations, like in the Heroku release phase
   4. Promote the lastest Docker image

## Environment

There are two main places where we can set up environment variables in Control Plane:

- **In `workload/container/env`** - those are container-specific and need to be set up individually for each container.

- **In `gvc/env`** - this is a "common" place to keep env vars which we can share among different workloads. Those
  common variables are not visible by default, and we should explicitly enable them via the `inheritEnv` property.

In general, `gvc/env` vars are useful for "app" types of workloads, e.g., `rails`, `sidekiq`, as they can easily share
common configs (the same way as on a Heroku app). They are not needed for non-app workloads, e.g., `redis`, `memcached`.

It is ok to keep most of the environment variables for non-production environments in the app templates as, in general,
they are not secret and can be committed to the repository.

It is also possible to set up a Secret store (of type Dictionary), which we can reference as, e.g.,
`cpln://secret/MY_SECRET_STORE_NAME/MY_SECRET_VAR_NAME`. In such a case, we also need to set up an app Identity and
proper Policy to access the secret.

```yaml
# In `templates/gvc.yml`:
spec:
  env:
    - name: MY_GLOBAL_VAR
      value: 'value'
    - name: MY_SECRET_GLOBAL_VAR
      value: 'cpln://secret/MY_SECRET_STORE_NAME/MY_SECRET_GLOBAL_VAR'

# In `templates/rails.yml`:
spec:
  containers:
    - name: rails
      env:
        - name: MY_LOCAL_VAR
          value: 'value'
        - name: MY_SECRET_LOCAL_VAR
          value: 'cpln://secret/MY_SECRET_STORE_NAME/MY_SECRET_LOCAL_VAR'
      inheritEnv: true # To enable global env inheritance
```

## Database

There are several options for a database setup on Control Plane:

- **Heroku Postgres**. It is the least recommended but simplest. We only need to provision the Postgres add-on on Heroku
  and copy its `XXXXXX_URL` connection string. This is good for quick testing, but unsuitable for the long term.

- **Control Plane container**. We can set it up as a workload using one of the default [Docker Hub](https://hub.docker.com/)
  images. However, such a setup lacks persistence between container restarts. We can use this only for an example or
  test app where the database doesn't keep any serious data and where such data is restorable.

- Any other cloud provider for Postgres, e.g., Amazon's RDS can be a quick go-to. Here are
  [instructions for setting up a free tier of RDS.](https://aws.amazon.com/premiumsupport/knowledge-center/free-tier-rds-launch/).

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

Additionally, we provide a default `postgres` template in this repo optimized for Control Plane and suitable for
development purposes.

## In-memory Databases

E.g., Redis, Memcached.

For development purposes, it's useful to set those up as Control Plane workloads, as in most cases they don't keep any
valuable data and can be safely restarted (sometimes), which doesn't affect application performance.

For production purposes or where restarts are not an option, you should use external cloud services.

We provide default `redis` and `memcached` templates in this repo optimized for Control Plane and suitable for
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
    # Run daily job at 2am
    schedule: 0  2  *  *  *
    # Never or OnFailure
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

You can create the cron workload by adding the template for it to the `.controlplane/templates` folder and running
`cpl apply-template my-template -a my-app`, where `my-template` is the name of the template file (`my-template.yml`).

Then to view the logs of the cron workload, you can run `cpl logs -a my-app -w my-template`.

## CLI Commands Reference

Click [here](/docs/commands.md) to see the commands.

You can also run:

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

- See `examples/` and `templates/` folders of this repo.
- See `.controlplane` directory of this live example:
  [react-webpack-rails-tutorial](https://github.com/shakacode/react-webpack-rails-tutorial/tree/master/.controlplane)
