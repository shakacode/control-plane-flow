# heroku-to-control-plane
Playbook for migrating from Heroku to Control Plane, controlplane.com

Adds `cpl` command to complement default CPLN cli `cpln` with "heroku style" scripting

## Instalation (atm just as local clone, not as gem)
- install CPLN cli (adds `cpln` command)
- install this repo locally, e.g.:
```sh
git clone https://github.com/shakacode/heroku-to-control-plane
```
- alias `cpl` command globally for easier access, e.g.:
```sh
# in some local shell startup scripts - .profile, .bashrc, etc.
alias cpl="~/projects/heroku-to-control-plane/cpl"
```
- project specific configs are kept in `.controlplane/` directory. `cpl` will pick those depending from which project folder tree it is executed. So, it is ok to run several projects with different configs w/o explicitly switching.

## Project changes
1. create `.controlplane` directory in your project and copy files from `templates` directory of this repo to something as following:
```sh
app_main_folder
  .controlplane
    controlplane.yml
    Dockerfile          # this is your app Dockerfile, with some CPLN changes
    entrypoint.sh       # app specific, edit as needed
```

2. copy your `Dockerfile` to `.controlplane/Dockerfile` and apply following changes:
```dockerfile
# adds `netcat` package (or whatever alternative way)
RUN apt-get update && apt-get install -y netcat

# copies `entrypoint.sh` to `/app` (or whatever alternative way)
COPY .controlplane/entrypoint.sh /app

# specify entrypoint script
ENTRYPOINT ["/app/entrypoint.sh"]

# run rails (or whatever alternative way)
CMD ["rails", "s"]
```
> NOTE: `netcat` is needed to enable correct `run` command functionality

3. edit `controlplane.yml` where necessary, e.g.:
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

## Commands:

### possible options
```sh
-a, --app XXX         app ref on CPLN (== GVC)
-w, --workload XXX    workload, where applicable

# applicable to some commands
--altlog              alternative non-streaming log implementation
--image XXX           use XXX image
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
- runs one-off replicas (analogue of `heroku run`)
- creates one-off workloads
- uses `cpln connect/exec` as execution method

> IMPORTANT: useful for development where needed interaction and network connection drops (and
> task crashing) is toleratable. For production tasks use `cpl runner`

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
- stable detached implementation, uses CPLN cron type of workloads and log streaming
- uses only async execution methods, more suitable for prod tasks
- has `altlog` log streaming implementation with only json-polling and no websockets. Less responsive but more stable, useful for CI tasks

```sh
cpl runner rails db:prepare -a $APP_NAME
cpl runner 'LOG_LEVEL=warn rails db:migrate' -a $APP_NAME

# uses more stable log streaming implementation
cpl runner rails db:prepare -a $APP_NAME --altlog

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
