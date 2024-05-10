# Steps to Migrate from Heroku to Control Plane

We recommend following along with
[this example project](https://github.com/shakacode/react-webpack-rails-tutorial).

1. [Clone the Staging Environment](#clone-the-staging-environment)
   - [Review Special Gems](#review-special-gems)
   - [Create a Minimum Bootable Config](#create-a-minimum-bootable-config)
2. [Create the Review App Process](#create-the-review-app-process)
   - [Database for Review Apps](#database-for-review-apps)
   - [Redis and Memcached for Review Apps](#redis-and-memcached-for-review-apps)
3. [Deploy to Production](#deploy-to-production)

## Clone the Staging Environment

By cloning the staging environment on Heroku, you can speed up the initial provisioning of the app on Control Plane
without compromising your current environment.

Consider migrating just the web dyno first, and get other types of dynos working afterward. You can also move the
add-ons to Control Plane later once the app works as expected.

First, create a new Heroku app with all the add-ons, copying the data from the current staging app.

Then, copy project-specific configs to a `.controlplane/` directory at the top of your project. `cpl` will pick those up
depending on which project folder tree it runs. Thus, this automates running several projects with different configs
without explicitly switching configs.

Edit the `.controlplane/controlplane.yml` file as needed. Note that the `my-app-staging` name used in the examples below
is defined in this file. See
[this example](https://github.com/shakacode/react-webpack-rails-tutorial/blob/master/.controlplane/controlplane.yml).

Before the initial setup, add the templates for the app to the `.controlplane/controlplane.yml` file, using the `setup_app_templates`
key, e.g.:

```yaml
my-app-staging:
  <<: *common
  setup_app_templates:
    - app
    - redis
    - memcached
    - rails
    - sidekiq
```

Note how the templates correspond to files in the `.controlplane/templates/` directory. These files will be used by the
`cpl setup-app` and `cpl apply-template` commands.

Ensure that env vars point to the Heroku add-ons in the template for the app (`.controlplane/templates/app.yml`). See
[this example](https://github.com/shakacode/react-webpack-rails-tutorial/blob/master/.controlplane/templates/gvc.yml).

After that, create a Dockerfile in `.controlplane/Dockerfile` for your deployment. See
[this example](https://github.com/shakacode/react-webpack-rails-tutorial/blob/master/.controlplane/Dockerfile).

You should have a folder structure similar to the following:

```sh
app_main_folder/
  .controlplane/
    Dockerfile          # Your app's Dockerfile, with some Control Plane changes.
    controlplane.yml
    entrypoint.sh       # App-specific - edit as needed.
    templates/
      app.yml
      memcached.yml
      rails.yml
      redis.yml
      sidekiq.yml
```

The example
[`.controlplane/` directory](https://github.com/shakacode/react-webpack-rails-tutorial/tree/master/.controlplane)
already contains these files.

Finally, check the app for any Heroku-specific code and update it, such as the `HEROKU_SLUG_COMMIT` env var and other
env vars beginning with `HEROKU_`. You should add some logic to check for the Control Plane equivalents - it might be
worth adding a `CONTROLPLANE` env var to act as a feature flag and help run different code for Heroku and Control Plane
until the migration is complete.

You might want to [review special gems](#review-special-gems) and
[create a minimum bootable config](#create-a-minimum-bootable-config).

At first, do the deployments from the command line. Then set up CI scripts to trigger the deployment upon merges to
master/main.

Use these commands for the initial setup and deployment:

```sh
# Provision infrastructure (one-time-only for new apps) using templates.
cpl setup-app -a my-app-staging

# Build and push image with auto-tagging, e.g., "my-app-staging:1_456".
cpl build-image -a my-app-staging --commit 456

# Prepare database.
cpl run -a my-app-staging --image latest -- rails db:prepare

# Deploy latest image.
cpl deploy-image -a my-app-staging

# Open app in browser.
cpl open -a my-app-staging
```

Then for promoting code upgrades:

```sh
# Build and push new image with sequential tagging, e.g., "my-app-staging:2".
cpl build-image -a my-app-staging

# Or build and push new image with sequential tagging and commit SHA, e.g., "my-app-staging:2_ABC".
cpl build-image -a my-app-staging --commit ABC

# Run database migrations (or other release tasks) with latest image, while app is still running on previous image.
# This is analogous to the release phase.
cpl run -a my-app-staging --image latest -- rails db:migrate

# Deploy latest image.
cpl deploy-image -a my-app-staging
```

### Review Special Gems

Make sure to review "special" gems which might be related to Heroku, e.g.:

- `rails_autoscale_agent`. It's specific to Heroku, so it must be removed.
- `puma_worker_killer`. In general, it's unnecessary on Control Plane, as Kubernetes containers will restart on their
  own logic and may not restart at all if everything is ok.
- `rack-timeout`. It could possibly be replaced with Control Plane's `timeout` option.

You can use the `CONTROLPLANE` env var to separate the gems, e.g.:

```ruby
# Gemfile
group :staging, :production do
	gem "rack-timeout"

  unless ENV.key?("CONTROLPLANE")
	  gem "rails_autoscale_agent"
    gem "puma_worker_killer"
  end
end
```

### Create a Minimum Bootable Config

You can try to create a minimum bootable config to migrate parts of your app gradually. To do that, follow these steps:

1. Rename the existing `application.yml` file to some other name (e.g., `application.old.yml`)
2. Create a new **minimal** `application.yml` file, e.g.:

```yaml
SECRET_KEY_BASE: "123"
# This should be enabled for `rails s`, not `rails assets:precompile`.
# DATABASE_URL: postgres://localhost:5432/dbname
# RAILS_SERVE_STATIC_FILES: "true"

# You will add whatever env vars are required here later.
```

3. Try running `RAILS_ENV=production CONTROLPLANE=true rails assets:precompile`
   (theoretically, this should work without any additional env vars)
4. Fix whatever code needs to be fixed and add missing env vars
   (the fewer env vars are needed, the cleaner the `Dockerfile` will be)
5. Enable `DATABASE_URL` and `RAILS_SERVE_STATIC_FILES` env vars
6. Try running `RAILS_ENV=production CONTROLPLANE=true rails s`
7. Fix whatever code needs to be fixed and add required env vars to `application.yml`
8. Try running your **production** entrypoint command, e.g.,
   `RAILS_ENV=production RACK_ENV=production CONTROLPLANE=true puma -C config/puma.rb`
9. Fix whatever code needs to be fixed and add required env vars to `application.yml`

Now you should have a minimal bootable config.

Then you can temporarily set the `LOG_LEVEL=debug` env var and disable unnecessary services to help with the process,
e.g.:

```yaml
DISABLE_SPRING: "true"
SCOUT_MONITOR: "false"
RACK_TIMEOUT_SERVICE_TIMEOUT: "0"
```

## Create the Review App Process

Add an entry for review apps to the `.controlplane/controlplane.yml` file. By adding a `match_if_app_name_starts_with`
key with the value `true`, any app that starts with the entry's name will use this config. Doing this allows you to
configure an entry for, e.g., `my-app-review`, and then create review apps starting with that name (e.g.,
`my-app-review-1234`, `my-app-review-5678`, etc.). Here's an example:

```yaml
  my-app-review:
    <<: *common
    match_if_app_name_starts_with: true
    setup_app_templates:
      - app
      - redis
      - memcached
      - rails
      - sidekiq
```

In your CI scripts, you can create a review app using some identifier (e.g., the number of the PR on GitHub).

```yaml
# On CircleCI, you can use `echo $CIRCLE_PULL_REQUEST | grep -Eo '[0-9]+$'` to extract the number of the PR.
PR_NUM=$(... extract the number of the PR here ...)
echo "export APP_NAME=my-app-review-$PR_NUM" >> $BASH_ENV

# Only create the app if it doesn't exist yet, as we may have multiple triggers for the review app
# (such as when a PR gets updated).
if ! cpl exists -a ${APP_NAME}; then
  cpl setup-app -a ${APP_NAME}
  echo "export NEW_APP=true" >> $BASH_ENV
fi

# The `NEW_APP` env var that we exported above can be used to either reset or migrate the database before deploying.
if [ -n "${NEW_APP}" ]; then
  cpl run -a ${APP_NAME} --image latest -- rails db:reset
else
  cpl run -a ${APP_NAME} --image latest -- rails db:migrate
fi
```

Then follow the same steps for the initial deployment or code upgrades.

### Database for Review Apps

For the review app resources, these should be handled as env vars in the template for the app
(`.controlplane/templates/app.yml`), .e.g.:

```yaml
- name: DATABASE_URL
  value: postgres://postgres:XXXXXXXX@cpln-XXXX-staging.XXXXXX.us-east-1.rds.amazonaws.com:5432/APP_GVC
```

Notice that `APP_GVC` is the app name, which is used as the database name on RDS, so that each review app gets its own
database on the one RDS instance used for all review apps, which would be, e.g., `my-app-review-1234`.

### Redis and Memcached for Review Apps

So long as no persistence is needed for Redis and Memcached, we have templates for workloads that should be sufficient
for review apps in the `templates/` directory of this repository. Using these templates results in considerable cost
savings compared to paying for the resources on Heroku.

```yaml
- name: MEMCACHE_SERVERS
  value: memcached.APP_GVC.cpln.local
- name: REDIS_URL
  value: redis://redis.APP_GVC.cpln.local:6379
```

## Deploy to Production

Only try deploying to production once staging and review apps are working well.

For simplicity, keep add-ons running on Heroku initially. You could move over the database to RDS first. However, it's a
bit simpler to isolate any differences in cost and performance by first moving over your compute to Control Plane.

Ensure that your Control Plane compute is in the AWS region `US-EAST-1`; otherwise, you'll have noticeable extra latency
with your calls to resources. You might also have egress charges from Control Plane.

Use the `cpl promote-app-from-upstream` command to promote the staging app to production.
