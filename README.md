# heroku-to-control-plane
Playbook for migrating from Heroku to Control Plane, controlplane.com

Idea of this playbook is to show how to move "heroku apps" to Controlplane and have some "heroku-style" cli
experience either temporary (while testing/migrating) or permanently.

From the higher perspective, heroku and heroku-cli are designed to make user life simple (as it can be), which hides
many implementation details under "heroku" abstractions. Controlplane and cpln-cli on the other side, gives you all the
raw power immediately to your fingers, which, however, you should know exactly how to use. And to have both worlds
simultaneously we are proposing a **mapping of ideas** and some **helper cli** based on templates to save lots
of cli typing.

## Concept mapping

On heroku everything runs as apps which mean an entity 1) running several process types, which heroku calls dynos
2) having addons - database, or some services 3) having common environment.
On Controlplane this can be mapped with GVC (Global Virtual Cloud). Such a cloud consists of Workloads, which can
practically be anything that can run as a container.

Lets set some main concepts (how we propose to map it):

| heroku | controlplane |
| --- | --- |
| *app* | *GVC* (Global Virutal Cloud) |
| *dyno* | *workload* |
| *addon* | either *workload* or external resource |
| *review app* | *GVC (app)* in staging *organization* |
| *staging env* | *GVC (app)* in staging *organization* |
| *production env* | *GVC (app)* in production *organization* |

On heroku dynos are specified in `Procfile` and configured in cli/ui, addons are configured only in cli/ui.
On Controlplane workloads are created either by *templates* (preferred way) or via cli/ui.

Which for typical rails app mean:

| function | examples | on heroku | on controlplane |
| --- | --- | --- | --- |
| web traffic | `rails`, `sinatra` | `web` dyno | workload with app image |
| background jobs | `sidekiq`, `resque` | `worker` dyno | workload with app image |
| db | `postgres`, `mysql` | addon | external provider or can be set up for dev/test with docker image (lacks persistence) |
| in-memory db | `redis`, `memcached` | addon | external provider or can be set up for dev/test with docker image (lacks persistence) |
| special something | `mailtrap` | addon | external provider or can be set up for dev/test with docker image (lacks persistence) |


## Installation (atm just as local clone, not as gem)
- install `node` (needed for cpln cli)

- install `ruby` (needed for this helpers)

- install controlplane cli (adds `cpln` command) and configure credentials
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
- project specific configs are kept in `.controlplane/` directory. `cpl` will pick those depending from which project folder tree it is executed. So, it is ok to run several projects with different configs w/o explicitly switching.


## Example flow for app build/deploy (with our helpers)
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

## Key features
- adds `cpl` command to complement default CPLN cli `cpln` with "heroku style" scripting
- easy to understand Heroku to CPLN conventions in setup, naming and cli
- `heroku run` and `heroku run:detached` **safe, production-ready** implementations for CPLN
- automatic sequential image tagging
- project-aware cli - makes easy to work with multiple projects from their own folders
- simplified `cpl` cli layer for "easy conventions" and default `cpln` cli for in-depth power

## Project changes
1. create `.controlplane` directory in your project and copy files from `templates` directory of this repo to something as following:
```sh
app_main_folder
  .controlplane
    controlplane.yml
    Dockerfile          # this is your app Dockerfile, with some CPLN changes
    entrypoint.sh       # app specific, edit as needed
```

2. edit `controlplane.yml` where necessary, e.g.:
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
  my-app-name:
    <<: *common
  my-app-name-review:
    <<: *common
    prefix: true
```

## Environment

There are 2 major places where environment variables can be set up in controlplane:

- in `workload/container/env` - those are container specific and need to be set up individually for each container

- in `gvc/env` - this is a "common" place to keep env vars which can be shared among different workloads. Those
common vars by default are not visible and should be explicitly enabled via `inheritEnv` property.

In general, `gvc/env` vars are useful for "app" type of workloads, e.g. `rails`, `sidekiq` as they can easily share
common configs (exactly same way as on heroku). And for non-app workloads e.g. `redis`, `memcached` are not needed.

It is ok to keep most of env values for non-production environments in app templates as in general they are not a
secret and can be committed to repo.

As well, if needed, it is possible to set up a Secret store (type Dictionary), which can be referenced as
e.g. `cpln://secret/MY_SECRET_STORE_NAME/MY_SECRET_VAR`. In such a case, it is also needed to set up app Identity and
proper Policy to access such secret.

```yaml
# in 'templates/gvc.yml'
spec:
  env:
    - name: MY_GOBAL_VAR
      value: 'value'
    - name: MY_SECRET_GLOBAL_VAR
      value: 'cpln://secret/MY_SECRET_STORE_NAME/MY_SECRET_VAR'

# in 'templates/rails.yml'
spec:
  containers:
    - name: rails
      env:
        - name: MY_LOCAL_VAR
          value: 'value'
        - name: MY_SECRET_LOCAL_VAR
          value: 'cpln://secret/MY_SECRET_STORE_NAME/MY_SECRET_VAR'
      inheritEnv: true # to enable global env inheritance
```


## Commands:

### possible options
```
-a, --app XXX         app ref on CPLN (== GVC)
-w, --workload XXX    workload, where applicable
-i, --image XXX       use XXX image
-c, --commit XXX      specify XXX as commit hash
```

### `build`
- builds and pushes image to CPLN
- atomatically assigns image numbers as `app:1`, `app:2`, etc

```sh
cpl build -a $APP_NAME
```

### `config`
- display current configs (global and project specific)

```sh
cpl config
```

### `delete`
```sh
# deletes whole app (gvc and images)
cpl delete -a $APP_NAME
```

### `exist`
```sh
# check if app (GVC) exists, useful in scripts, e.g.:
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
```sh
# opens app endpoint url in browser
cpl open -a $APP_NAME
```

### `promote`
```sh
# promotes latest image to app workloads
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
```

### `run`
- runs one-off *ineractive* replicas (close analogue of `heroku run`)
- creates one-off workloads
- uses `cpln connect/exec` as execution method
- may not work correctly with tasks over 5 min (CPLN scaling bug atm)

> IMPORTANT: useful for development where needed interaction and network connection drops (and
> task crashing) is toleratable. For production tasks better use `cpl runner`

```sh
# opens shell (bash by default)
cpl run -a $APP_NAME

# runs commmand, displays output, quits (as command quits)
cpl run ls / -a $APP_NAME
cpl run rails db:migrate:status -a $APP_NAME

# runs command, keeps shell opened
cpl run rails c -a $APP_NAME
```

### `runner`
- runs one-off *non-interactive* replicas (close analogue of `heroku run:detached`)
- stable detached implementation, uses CPLN cron type of workloads and log streaming
- uses only async execution methods, more suitable for prod tasks
- has alternative log fetch implementation with only json-polling and no websockets. Less responsive but more stable, useful for CI tasks

```sh
cpl runner rails db:prepare -a $APP_NAME
cpl runner 'LOG_LEVEL=warn rails db:migrate' -a $APP_NAME

# uses other image
cpl runner rails db:migrate -a $APP_NAME --image /some/full/image/path

# uses latest app image (which may be not promoted yet)
cpl runner rails db:migrate -a $APP_NAME --image latest
```

### `setup`
- applies app specific configs to general templates (e.g. for every review-app)
- publishes (creates/updates) those at CPLN
```sh
# applies single template
cpl setup redis -a $APP_NAME

# applies several templates (practically creating full app)
cpl setup gvc postgres redis rails -a $APP_NAME
```
- template variables
```
APP_GVC      - basically gvc or app name
APP_LOCATION - default location
APP_ORG      - org
APP_IMAGE    - image
```

## Examples

See `examples/` and `templates/` folders of this repo.
