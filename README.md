# heroku-to-control-plane
Playbook for migrating from [Heroku](heroku.com) to [Control Plane](controlplane.com)

The idea of this playbook is to show how to move "Heroku apps" to "Control Plane apps" while keeping some "Heroku-style"
simplified CLI experience either temporarily while testing/migrating or permanently.

From a higher perspective, Heroku has designed its CLI to simplify user life (as possible :wink:), which hides
many implementation details under "Heroku" abstractions and naming conventions.
Control Plane and Control Plane CLI, on the other side, give you all the raw power immediately to your fingers.
However, you should know precisely how to use it.

Thus to have both worlds simultaneously, we propose **concept mapping** and some **helper CLI** based
on templates to save lots of day-to-day typing (and human errors).

1. [Key features](#key-features)
2. [Concept mapping](#concept-mapping)
3. [Installation](#installation)
4. [Example CLI flow for application build/deployment](#example-cli-flow-for-application-builddeployment)
5. [Example project changes](#example-project-changes)
6. [Environment](#environment)
7. [Database](#database)
8. [In-memory databases](#in-memory-databases)
9. [CLI commands reference](#cli-commands-reference)
10. [Examples](#examples)

## Key features

- adds `cpl` command to complement default Control Plane CLI (`cpln`) with "Heroku style scripting"
- easy to understand Heroku to Control Plane conventions in setup, naming, and cli
- `heroku run` and `heroku run:detached` **safe, production-ready** implementations for Control Plane
- automatic sequential release tagging for images
- project-aware CLI - makes it easy to work with multiple projects from their dedicated folders
- simplified `cpl` CLI layer for "easy conventions" and default `cpln` CLI for in-depth power

## Concept mapping

On Heroku, everything runs as an app which means an entity that:
1) runs several process types, which Heroku calls dynos
2) has add-ons - database or some services
3) has common environment

On Control Plane, we can map Heroku app to GVC (Global Virtual Cloud). Such a cloud consists of Workloads, which can
be anything that can run as a container.

Let's set some main concepts (how we propose to map it):

| Heroku | Control Plane |
| --- | --- |
| *app* | *GVC* (Global Virutal Cloud) |
| *dyno* | *workload* |
| *addon* | either *workload* or external resource |
| *review app* | *GVC (app)* in staging *organization* |
| *staging env* | *GVC (app)* in staging *organization* |
| *production env* | *GVC (app)* in production *organization* |

On Heroku, dynos are specified in `Procfile` and configured in CLI/UI; addons are configured only in CLI/UI.
On Controlplanem, workloads are created either by *templates* (preferred way) or via CLI/UI.

Which for the typical rails app means:

| function | examples | on Heroku | on Control Plane |
| --- | --- | --- | --- |
| web traffic | `rails`, `sinatra` | `web` dyno | workload with app image |
| background jobs | `sidekiq`, `resque` | `worker` dyno | workload with app image |
| db | `postgres`, `mysql` | addon | external provider or can be set up for dev/test with docker image (lacks persistence between restarts) |
| in-memory db | `redis`, `memcached` | addon | external provider or can be set up for dev/test with docker image (lacks persistence restarts) |
| special something | `mailtrap` | addon | external provider or can be set up for dev/test with docker image (lacks persistence restarts) |


## Installation

Note: Atm is just a local clone, not a ruby gem or node package

- install `node` (required for Control Plane CLI)

- install `ruby` (required for these helpers)

- install Control Plane CLI (adds `cpln` command) and configure credentials
```sh
npm install -g @controlplane/cli
cpln login
```

- install this repo locally, alias `cpl` command globally for easier access, e.g.:
```sh
git clone https://github.com/shakacode/heroku-to-control-plane

# in some local shell startup script - .profile, .bashrc, etc.
alias cpl="~/projects/heroku-to-control-plane/cpl"
```

- copy project-specific configs to the `.controlplane/` directory. `cpl` will pick those depending on which project
folder tree it runs. So, running several projects with different configs w/o explicitly switching is automated.

## Example CLI flow for application build/deployment
```sh
# provision infrastructure (one-time for new apps only)
cpl setup gvc postgres redis memcached rails sidekiq -a myapp

# build and push image with auto-tagging 'myapp:1_456'
cpl build -a myapp --commit 456

# prepare database
cpl runner rails db:prepare -a myapp --image latest

# promote latest image
cpl promote -a myapp

# open app in browser
cpl open -a myapp
```

## Example project changes
1. Create the `.controlplane` directory in your project and copy files from the `templates` directory of this repo to
something as follows:
```sh
app_main_folder/
  .controlplane/
    controlplane.yml
    Dockerfile          # this is your app Dockerfile, with some CPLN changes
    entrypoint.sh       # app specific, edit as needed
    templates/
      gvc.yml
      memcached.yml
      postgres.yml
      rails.yml
      redis.yml
      sidekiq.yml
```

2. Edit `controlplane.yml` where necessary, e.g.:
```yaml
aliases:
  common: &common
    org: my-org-name
    location: aws-us-east-2
    one_off_workload: rails
    app_workloads:
      - rails
      - sidekiq
    additional_workloads:
      # - postgres # atm deployed and started manually
      - redis
      - memcached

apps:
  my-app-name-staging:
    <<: *common
  my-app-name-review:
    <<: *common
    prefix: true
```

## Environment

There are two main places where we can set up environment variables in Control Plane:

- In `workload/container/env` - those are container specific and need to be set up individually for each container

- In `gvc/env` - this is a "common" place to keep env vars which we can share among different workloads.
Those common variables are not visible by default, and we should explicitly enable them via `inheritEnv` property.

In general, `gvc/env` vars are useful for "app" types of workloads, e.g., `rails`, `sidekiq`, as they can easily share
common configs (the same way as on Heroku). And they are not needed for non-app workloads,
e.g., `redis`, `memcached`.

It is ok to keep most of the environment variables for non-production environments in the app templates as, in general,
they are not secret and can be committed to the repository.

It is also possible to set up a Secret store (of type Dictionary), which we can reference as,
e.g., `cpln://secret/MY_SECRET_STORE_NAME/MY_SECRET_VAR_NAME`.
In such a case, we also need to set up an app Identity and proper Policy to access the secret.

```yaml
# in 'templates/gvc.yml'
spec:
  env:
    - name: MY_GOBAL_VAR
      value: 'value'
    - name: MY_SECRET_GLOBAL_VAR
      value: 'cpln://secret/MY_SECRET_STORE_NAME/MY_SECRET_GLOBAL_VAR'

# in 'templates/rails.yml'
spec:
  containers:
    - name: rails
      env:
        - name: MY_LOCAL_VAR
          value: 'value'
        - name: MY_SECRET_LOCAL_VAR
          value: 'cpln://secret/MY_SECRET_STORE_NAME/MY_SECRET_LOCAL_VAR'
      inheritEnv: true # to enable global env inheritance
```

## Database

There are several options for a database setup on Control Plane.

1. Heroku Postgres. It is the least recommended but dead easy. We only need to provision the Postgres addon on Heroku and
pick its `XXXXXX_URL` connection string. Good for quick testing, but not suitable long term.

2. Control Plane container. We can set it up as a workload using one of the default Dockerhub images.
However, atm, such a setup lacks persistence between container restarts.
We can use this only for a pet, tutorial, or even review app project,
where the database doesn't keep any serious data and where such data is restorable.

3. Any other cloud provider Postgres, e.g., Amazon's RDS can be a quick go-to.

Tip: if you are using RDS for dev/testing purposes, you might consider running such a database publically
accessible (actually, Heroku does for all its Postgres databases unless private spaces). Then we can connect to
such a database from everywhere with only the correct username/password.

By default, we have structured our templates to accomplish this with only a single free-tier or low-tier AWS RDS instance
that can serve all your dev/qa needs for small-medium applications, e.g., as follows:
```
aws-rds-single-pg-instance
  mydb-staging
  mydb-review-111
  mydb-review-222
  mydb-review-333
```

Additionally, we provide default `postgres` template in this repo optimized for Control Plane and suitable
for development purposes.

## In-memory databases

E.g. Redis, Memcached.

For development purposes it is useful to set up those as a Control Plane workloads as in most cases they don't keep any
valuable datas and can be safely restarted (sometimes), which doesn't affect application performance.

For production purposes or where restarts is totally not an option, it should be used external cloud services.

We provide default `redis` and `memcached` templates in this repo optimized for Control Plane and suitable
for development purposes.

## CLI commands reference:

### Common Options

```
-a, --app XXX         app ref on Control Plane (== GVC)
```

This `-a` option is used in most of the commands and will pick all other app configurations from the project-specific
`controlplane.yml` template.

### `build`

- builds and pushes the image to Control Plane
- automatically assigns image numbers as `app:1`, `app:2`, etc
- uses `.controlplane/Dockerfile`

```sh
cpl build -a $APP_NAME
```

### `config`

- displays current configs (global and project specific)

```sh
# show global config
cpl config

# show global and app specific config
cpl config -a $APP_NAME
```

### `delete`

- deletes the whole app (gvc with all workloads and all images)
- will ask for explicit user confirmation

```sh
cpl delete -a $APP_NAME
```

### `exist`

- shell check if an application (GVC) exists, useful in scripts, e.g.:

```sh
if [ cpl exist -a $APP_NAME ]; ...
```

### `logs`

- light wrapper to display tailed raw logs for app/workload syntax

```sh
# display logs for default workload (== one_off.workload)
cpl logs -a $APP_NAME

# display logs for other workload
cpl logs -a $APP_NAME -w $WORKLOAD_NAME
```

### `open`

- opens app endpoint URL in the default browser

```sh
cpl open -a $APP_NAME

# open endpoint of other non-default workload
cpl open -a $APP_NAME -w $WORKLOAD_NAME
```

### `promote`

- promotes the latest image to app workloads

```sh
cpl promote -a $APP_NAME
```

### `ps`

```sh
# shows running replicas in app
cpl ps -a $APP_NAME

# starts all workloads in app
cpl ps:start -a $APP_NAME

# stops all workloads in app
cpl ps:stop -a $APP_NAME

# force redeploy of all workloads in app
cpl ps:restart -a $APP_NAME
```

### `run`

- runs one-off **_interactive_** replicas (analog of `heroku run`)
- uses `Standard` workload type, `cpln exec` as the execution method with CLI streaming
- may not work correctly with tasks over 5 min (Control Plane scaling bug atm)

> IMPORTANT: useful for development where it is needed interaction and network connection drops (and
> task crashing) is toleratable. For production tasks better use `cpl runner`

```sh
# opens shell (bash by default)
cpl run -a $APP_NAME

# runs commmand, displays output, quits (as command quits)
cpl run ls / -a $APP_NAME
cpl run rails db:migrate:status -a $APP_NAME

# runs command, keeps shell opened
cpl run rails c -a $APP_NAME

# use different image (which may be not promoted yet)
cpl run xxx -a $APP_NAME --image appimage:123 # exact image name
cpl run xxx -a $APP_NAME --image latest       # picks latest sequential image
```

### `runner`

- runs one-off **_non-interactive_** replicas (close analog of `heroku run:detached`)
- uses `Cron` workload type with log async fetching
- implemented with only async execution methods, more suitable for prod tasks
- has alternative log fetch implementation with only JSON-polling and no WebSockets.
Less responsive but more stable, useful for CI tasks

```sh
cpl runner rails db:prepare -a $APP_NAME
cpl runner 'LOG_LEVEL=warn rails db:migrate' -a $APP_NAME

# uses other image
cpl runner rails db:migrate -a $APP_NAME --image /some/full/image/path

# uses latest app image (which may be not promoted yet)
cpl runner rails db:migrate -a $APP_NAME --image latest

# use different image (which may be not promoted yet)
cpl runner xxx -a $APP_NAME --image appimage:123 # exact image name
cpl runner xxx -a $APP_NAME --image latest       # picks latest sequential image
```

### `setup`

- applies application-specific configs from templates (e.g., for every review-app)
- publishes (creates or updates) those at Control Plane infrastructure
- picks templates from `.controlplane/templates` folder
- templates are ordinary Control Plane templates but with variable preprocessing

```sh
# applies single template
cpl setup redis -a $APP_NAME

# applies several templates (practically creating full app)
cpl setup gvc postgres redis rails -a $APP_NAME
```

- preprocessed template variables

```
APP_GVC      - basically gvc or app name
APP_LOCATION - default location
APP_ORG      - org
APP_IMAGE    - will use latest app image
```

## Examples

See `examples/` and `templates/` folders of this repo.
