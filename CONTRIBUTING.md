# Contributing

## Installation

Rather than installing `cpl` as a Ruby gem, install this repo locally and alias the `cpl` command globally for easier
access, e.g.:

```sh
git clone https://github.com/shakacode/heroku-to-control-plane

# Create an alias in some local shell startup script, e.g., `.profile`, `.bashrc`, etc.
alias cpl="~/projects/heroku-to-control-plane/bin/cpl"
```

## Linting/Testing

Before committing or pushing code, be sure to:

- Run `bundle exec rake update_command_docs` to sync any doc changes made in the source code to the docs
- Run `bundle exec rubocop -a` to fix any linting errors
- Run `bundle exec rspec` to run the test suite

You can also install [overcommit](https://github.com/sds/overcommit) and let it automatically check for you:

```sh
gem install overcommit

overcommit --install
```

## Debugging

1. Use the `--verbose` option to see more detailed logs.
2. Use the `--trace` option to see full logging of HTTP requests. Warning, this will display keys to your logs or console.
1. Add a breakpoint (`debugger`) to any line of code you want to debug.
2. Modify the `lib/command/test.rb` file to trigger the code you want to test. To simulate a command, you can use
   `Cpl::Cli.start` (e.g., `Cpl::Cli.start(["deploy-image", "-a", "my-app-name"])` would be the same as running
   `cpl deploy-image -a my-app-name`).
3. Run the `test` command in your test app with a `.controlplane` directory.

```sh
cpl test
```
