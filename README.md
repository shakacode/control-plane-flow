# Heroku to Control Plane

_A playbook for migrating from [Heroku](https://heroku.com) to [Control Plane](https://controlplane.com)_

This playbook shows how to move "Heroku apps" to "Control Plane workloads" via an open-source `cpl` CLI on top of Control Plane's `cpln` CLI.

Heroku provides a UX and CLI that enables easy publishing of Ruby on Rails and other apps. This ease of use comes via many "Heroku" abstractions and naming conventions.
Control Plane, on the other hand, gives you access to raw cloud computing power. However, you need to know precisely how to use it.

To simplify migration to and usage of Control Plane for Heroku users, this repository provides a **concept mapping** and a **helper CLI** based on templates to save lots of day-to-day typing (and human errors).

1. [Key features](#key-features)
2. [Concept mapping](#concept-mapping)
3. [Installation](#installation)
4. [Example CLI flow for application build/deployment](#example-cli-flow-for-application-builddeployment)
5. [Example project modifications for Control Plane](#example-project-modifications-for-control-plane)
6. [Environment](#environment)
7. [Database](#database)
8. [In-memory databases](#in-memory-databases)
9. [CLI commands reference](#cli-commands-reference)
10. [Mapping of Heroku Commands to `cpl` and `cpln`](#mapping-of-heroku-commands-to-cpl-and-cpln)
11. [Examples](#examples)
12. [Migrating Postgres database from Heroku infrastructure](/postgres.md)
13. [Migrating Redis database from Heroku infrastructure](/redis.md)

## Key features

- A `cpl` command to complement the default Control Plane `cpln` command with "Heroku style scripting." The Ruby source can serve as inspiration for your own scripts.
- Easy to understand Heroku to Control Plane conventions in setup and naming.
- **Safe, production-ready** equivalents of `heroku run` and `heroku run:detached` for Control Plane.
- Automatic sequential release tagging for Docker images.
- A project-aware CLI which enables working on multiple projects.

## Concept mapping

On Heroku, everything runs as an app, which means an entity that:

1. Runs code from a Git repo
2. Runs several process types, as defined in the `Procfile`
3. Has dynos, which are Linux containers that run these process types
4. Has add-ons, including the database and other services
5. Has common environment variables

On Control Plane, we can map a Heroku app to a GVC (Global Virtual Cloud). Such a cloud consists of workloads, which can be anything that can run as a container.

**Mapping of Concepts:**

| Heroku           | Control Plane                               |
| ---------------- | ------------------------------------------- |
| _app_            | _GVC_ (Global Virtual Cloud)                |
| _dyno_           | _workload_                                  |
| _add-on_         | either a _workload_ or an external resource |
| _review app_     | _GVC (app)_ in staging _organization_       |
| _staging env_    | _GVC (app)_ in staging _organization_       |
| _production env_ | _GVC (app)_ in production _organization_    |

On Heroku, dyno types are specified in the `Procfile` and configured via the CLI/UI; add-ons are configured only via the CLI/UI.
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

**Note:** `cpl` CLI is configured via a local clone clone of this repo. We may publish it later as a Ruby gem or Node package.

1. Install `node` (required for Control Plane CLI).
2. Install `ruby` (required for these helpers).
3. Install Control Plane CLI (adds `cpln` command) and configure credentials.

```sh
npm install -g @controlplane/cli
cpln login
```

4. Install this repo locally and alias `cpl` command globally for easier access, e.g.:

```sh
git clone https://github.com/shakacode/heroku-to-control-plane

# Create an alias in some local shell startup script, e.g., `.profile`, `.bashrc`, etc.
alias cpl="~/projects/heroku-to-control-plane/cpl"
```

- For each Git project that you want to deploy to Control Plane, copy project-specific configs to a `.controlplane` directory at the top of your project. `cpl` will pick those up depending on which project
  folder tree it runs. Thus, this automates running several projects with different configs without explicitly switching configs.

5. Create a `Dockerfile` for your production deployment. See [this example](https://github.com/shakacode/react-webpack-rails-tutorial/blob/master/.controlplane/Dockerfile).

## Example CLI flow for application build/deployment

**Notes:**

1. `myapp` is an app name defined in the `.controlplane/controlplane.yml` file, such as `ror-tutorial` in [this `controlplane.yml` file](https://github.com/shakacode/react-webpack-rails-tutorial/blob/master/.controlplane/controlplane.yml).
2. Other files in the `.controlplane/templates` directory are used by the `cpl setup` command.

```sh
# Provision infrastructure (one-time-only for new apps) using templates.
# Note how the arguments correspond to files in the `.controlplane/templates` directory.
cpl setup gvc postgres redis memcached rails sidekiq -a myapp

# Build and push image with auto-tagging "myapp:1_456".
cpl build-image -a myapp --commit 456

# Prepare database.
cpl run:detached rails db:prepare -a myapp --image latest

# Promote latest image.
cpl promote-image -a myapp

# Open app in browser.
cpl open -a myapp
```

## Example project modifications for Control Plane

_See this for a complete example._

To learn how to migrate an app, we recommend that you first follow along with [this example project](https://github.com/shakacode/react-webpack-rails-tutorial).

1. Create the `.controlplane` directory at the top of your project and copy files from the `templates` directory of this repo to
   something as follows:

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

The example [`.controlplane` directory](https://github.com/shakacode/react-webpack-rails-tutorial/tree/master/.controlplane) already contains these files.

2. Edit your `controlplane.yml` file as needed. For example, see [this `controlplane.yml` file](https://github.com/shakacode/react-webpack-rails-tutorial/blob/master/.controlplane/controlplane.yml).

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
    # Allows running the command `cpl pipeline-promote my-app-staging` to promote the staging app to production.
    upstream: my-app-staging
  my-app-other:
    <<: *common
    # You can specify a different `Dockerfile` relative to the `.controlplane` directory (default is just "Dockerfile").
    dockerfile: ../some_other/Dockerfile
```

3. We recommend that you try out the commands listed in [the example](https://github.com/shakacode/react-webpack-rails-tutorial/blob/master/.controlplane/readme.md). These steps will guide you through:
   1. Provision the GVC and workloads
   2. Build the Docker image
   3. Run Rails migrations, like in the Heroku release phase
   4. Promote the lastest Docker image

## Environment

There are two main places where we can set up environment variables in Control Plane:

- **In `workload/container/env`** - those are container-specific and need to be set up individually for each container.

- **In `gvc/env`** - this is a "common" place to keep env vars which we can share among different workloads.
  Those common variables are not visible by default, and we should explicitly enable them via the `inheritEnv` property.

In general, `gvc/env` vars are useful for "app" types of workloads, e.g., `rails`, `sidekiq`, as they can easily share
common configs (the same way as on a Heroku app). They are not needed for non-app workloads,
e.g., `redis`, `memcached`.

It is ok to keep most of the environment variables for non-production environments in the app templates as, in general,
they are not secret and can be committed to the repository.

It is also possible to set up a Secret store (of type Dictionary), which we can reference as,
e.g., `cpln://secret/MY_SECRET_STORE_NAME/MY_SECRET_VAR_NAME`.
In such a case, we also need to set up an app Identity and proper Policy to access the secret.

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

1. **Heroku Postgres**. It is the least recommended but simplest. We only need to provision the Postgres add-on on Heroku and
   copy its `XXXXXX_URL` connection string. This is good for quick testing, but unsuitable for the long term.

2. **Control Plane container**. We can set it up as a workload using one of the default [Docker Hub](https://hub.docker.com/) images.
   However, such a setup lacks persistence between container restarts.
   We can use this only for an example or test app
   where the database doesn't keep any serious data and where such data is restorable.

3. Any other cloud provider for Postgres, e.g., Amazon's RDS can be a quick go-to. Here are [instructions for setting up a free tier of RDS.](https://aws.amazon.com/premiumsupport/knowledge-center/free-tier-rds-launch/).

**Tip:** If you are using RDS for development/testing purposes, you might consider running such a database publicly
accessible (Heroku actually does that for all of its Postgres databases unless they are within private spaces). Then we can connect to
such a database from everywhere with only the correct username/password.

By default, we have structured our templates to accomplish this with only a single free tier or low tier AWS RDS instance
that can serve all your development/testing needs for small/medium applications, e.g., as follows:

```
aws-rds-single-pg-instance
  mydb-staging
  mydb-review-111
  mydb-review-222
  mydb-review-333
```

Additionally, we provide a default `postgres` template in this repo optimized for Control Plane and suitable
for development purposes.

## In-memory databases

E.g. Redis, Memcached.

For development purposes, it's useful to set those up as Control Plane workloads, as in most cases they don't keep any
valuable data and can be safely restarted (sometimes), which doesn't affect application performance.

For production purposes or where restarts are not an option, you should use external cloud services.

We provide default `redis` and `memcached` templates in this repo optimized for Control Plane and suitable
for development purposes.

## CLI commands reference:

### Common Options

```
-a XXX, --app XXX         app ref on Control Plane (GVC)
```

This `-a` option is used in most of the commands and will pick all other app configurations from the project-specific
`.controlplane/controlplane.yml` file.

<!-- COMMANDS_BEGIN -->

### `build-image`

- Builds and pushes the image to Control Plane
- Automatically assigns image numbers, e.g., `app:1`, `app:2`, etc.
- Uses `.controlplane/Dockerfile`

```sh
cpl build-image -a $APP_NAME
```

### `config`

- Displays current configs (global and app-specific)

```sh
# Shows the global config.
cpl config

# Shows both global and app-specific configs.
cpl config -a $APP_NAME
```

### `delete`

- Deletes the whole app (GVC with all workloads and all images)
- Will ask for explicit user confirmation

```sh
cpl delete -a $APP_NAME
```

### `env`

- Displays app-specific environment variables

```sh
cpl env -a $APP_NAME
```

### `exist`

- Shell-checks if an application (GVC) exists, useful in scripts, e.g.:

```sh
if [ cpl exist -a $APP_NAME ]; ...
```

### `latest-image`

- Displays the latest image name

```sh
cpl latest-image -a $APP_NAME
```

### `logs`

- Light wrapper to display tailed raw logs for app/workload syntax

```sh
# Displays logs for the default workload (`one_off_workload`).
cpl logs -a $APP_NAME

# Displays logs for a specific workload.
cpl logs -a $APP_NAME -w $WORKLOAD_NAME
```

### `open`

- Opens the app endpoint URL in the default browser

```sh
# Opens the endpoint of the default workload (`one_off_workload`).
cpl open -a $APP_NAME

# Opens the endpoint of a specific workload.
cpl open -a $APP_NAME -w $WORKLOAD_NAME
```

### `promote-image`

- Promotes the latest image to app workloads

```sh
cpl promote-image -a $APP_NAME
```

### `ps`

- Shows running replicas in app

```sh
# Shows running replicas in app, for all workloads.
cpl ps -a $APP_NAME

# Shows running replicas in app, for a specific workload.
cpl ps -a $APP_NAME -w $WORKLOAD_NAME
```

### `ps:restart`

- Forces redeploy of workloads in app

```sh
# Forces redeploy of all workloads in app.
cpl ps:restart -a $APP_NAME

# Forces redeploy of a specific workload in app.
cpl ps:restart -a $APP_NAME -w $WORKLOAD_NAME
```

### `ps:start`

- Starts workloads in app

```sh
# Starts all workloads in app.
cpl ps:start -a $APP_NAME

# Starts a specific workload in app.
cpl ps:start -a $APP_NAME -w $WORKLOAD_NAME
```

### `ps:stop`

- Stops workloads in app

```sh
# Stops all workloads in app.
cpl ps:stop -a $APP_NAME

# Stops a specific workload in app.
cpl ps:stop -a $APP_NAME -w $WORKLOAD_NAME
```

### `run`

- Runs one-off **_interactive_** replicas (analog of `heroku run`)
- Uses `Standard` workload type and `cpln exec` as the execution method, with CLI streaming
- May not work correctly with tasks that last over 5 minutes (there's a Control Plane scaling bug at the moment)

> **IMPORTANT:** Useful for development where it's needed for interaction, and where network connection drops and
> task crashing are tolerable. For production tasks, it's better to use `cpl run:detached`.

```sh
# Opens shell (bash by default).
cpl run -a $APP_NAME

# Runs command, displays output, and exits shell.
cpl run ls / -a $APP_NAME
cpl run rails db:migrate:status -a $APP_NAME

# Runs command and keeps shell open.
cpl run rails c -a $APP_NAME

# Uses a different image (which may not be promoted yet).
cpl run rails db:migrate -a $APP_NAME --image appimage:123 # Exact image name
cpl run rails db:migrate -a $APP_NAME --image latest       # Latest sequential image
```

### `run:detached`

- Runs one-off **_non-interactive_** replicas (close analog of `heroku run:detached`)
- Uses `Cron` workload type with log async fetching
- Implemented with only async execution methods, more suitable for production tasks
- Has alternative log fetch implementation with only JSON-polling and no WebSockets
- Less responsive but more stable, useful for CI tasks

```sh
cpl run:detached rails db:prepare -a $APP_NAME
cpl run:detached 'LOG_LEVEL=warn rails db:migrate' -a $APP_NAME

# Uses some other image.
cpl run:detached rails db:migrate -a $APP_NAME --image /some/full/image/path

# Uses latest app image (which may not be promoted yet).
cpl run:detached rails db:migrate -a $APP_NAME --image latest

# Uses a different image (which may not be promoted yet).
cpl run:detached rails db:migrate -a $APP_NAME --image appimage:123 # Exact image name
cpl run:detached rails db:migrate -a $APP_NAME --image latest       # Latest sequential image
```

### `setup`

- Applies application-specific configs from templates (e.g., for every review-app)
- Publishes (creates or updates) those at Control Plane infrastructure
- Picks templates from the `.controlplane/templates` directory
- Templates are ordinary Control Plane templates but with variable preprocessing

**Preprocessed template variables:**

```
APP_GVC      - basically GVC or app name
APP_LOCATION - default location
APP_ORG      - organization
APP_IMAGE    - will use latest app image
```

```sh
# Applies single template.
cpl setup redis -a $APP_NAME

# Applies several templates (practically creating full app).
cpl setup gvc postgres redis rails -a $APP_NAME
```

<!-- COMMANDS_END -->

## Mapping of Heroku Commands to `cpl` and `cpln`

**`[WIP]`**

| Heroku Command             | `cpl` or `cpln` |
| -------------------------- | --------------- |
| `heroku ps`                | `cpl ps`        |
| `heroku config`            | ?               |
| `heroku maintenance`       | ?               |
| `heroku logs`              | `cpl logs`      |
| `heroku pg`                | ?               |
| `heroku pipelines:promote` | `cpl promote`   |
| `heroku psql`              | ?               |
| `heroku redis`             | ?               |
| `heroku releases`          | ?               |

## Examples

1. See `examples/` and `templates/` folders of this repo.
2. See `.controlplane` directory of this live example: [react-webpack-rails-tutorial](https://github.com/shakacode/react-webpack-rails-tutorial/tree/master/.controlplane)
