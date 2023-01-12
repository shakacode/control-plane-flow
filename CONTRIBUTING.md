# Contributing

## Linting
Be sure to run `rubocop -a` before committing code.

## Debugging

1. Install gem: `gem install debug`
2. Require: Add a `require "debug"` statement to the file you want to debug.
3. Add breakpoint: Add a `debugger` statement to the line you want to debug.
4. Modify the `lib/command/test.rb` file to triggger the code that you want to run.
5. Run the test in your test app with a `.controlplane` directory. `cpl test -a my-app-name`
