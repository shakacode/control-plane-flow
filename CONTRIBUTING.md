# Contributing

## Installation

Rather than installing `cpflow` as a Ruby gem, install this repo locally and alias the `cpflow` command globally for easier
access, e.g.:

```sh
git clone https://github.com/shakacode/control-plane-flow

# Create an alias in some local shell startup script, e.g., `.profile`, `.bashrc`, etc.
alias cpflow="~/projects/control-plane-flow/bin/cpflow"
```

## Linting

Before committing or pushing code, be sure to:

- Run `bundle exec rake update_command_docs` to sync any doc changes made in the source code to the docs
- Run `bundle exec rubocop -a` to fix any linting errors

You can also install [overcommit](https://github.com/sds/overcommit) and let it automatically check for you:

```sh
gem install overcommit

overcommit --install
```

## Testing

We use real apps for the tests. You'll need to have full access to a Control Plane org, and then set it as the env var `CPLN_ORG` when running the tests (or in the `.env` file):

```sh
CPLN_ORG=your-org-for-tests bundle exec rspec
```

Alternatively, you might have a `.envrc` file with:

```sh
export CPLN_ORG=shakacode-heroku-to-control-plane-ci
export RSPEC_RETRY_RETRY_COUNT=1
```

Tests are separated between fast and slow. Slow tests can take a long time and usually involve building / deploying images and waiting for workloads to be ready / not ready, so they should only be run once in a while.

If you add a slow test, tag it with `slow`. Tests without a `slow` tag are considered fast by default.

To run fast tests:

```sh
CPLN_ORG=your-org-for-tests bundle exec rspec --tag ~slow
```

To run slow tests:

```sh
CPLN_ORG=your-org-for-tests bundle exec rspec --tag slow
```

## Debugging

1. Use the `--verbose` option to see more detailed logs.
2. Use the `--trace` option to see full logging of HTTP requests. Warning, this will display keys to your logs or console.
1. Add a breakpoint (`debugger`) to any line of code you want to debug.
2. Modify the `lib/command/test.rb` file to trigger the code you want to test. To simulate a command, you can use
   `run_cpflow_command` (e.g., `run_cpflow_command("deploy-image", "-a", "my-app-name")` would be the same as running
   `cpflow deploy-image -a my-app-name`).
3. Run the `test` command in your test app with a `.controlplane` directory.

```sh
cpflow test
```
