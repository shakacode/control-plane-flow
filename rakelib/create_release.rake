# frozen_string_literal: true

require "English"

desc("Releases the gem package using the given version.

  IMPORTANT: the gem version must be in valid rubygem format (no dashes).
  This task depends on the gem-release ruby gem.

  1st argument: The new version in rubygem format (no dashes). Pass no argument to
                automatically perform a patch version bump.
  2nd argument: Perform a dry run by passing 'true' as a second argument.

  Example: `rake create_release[2.1.0,false]`")

task :create_release, %i[gem_version dry_run] do |_t, args|
  args_hash = args.to_hash

  is_dry_run = object_to_boolean(args_hash[:dry_run])
  gem_version = args_hash.fetch(:gem_version, "").strip
  gem_root = File.expand_path("..", __dir__)

  update_the_local_project
  ensure_there_is_nothing_to_commit

  Dir.chdir(gem_root) do
    # See https://github.com/svenfuchs/gem-release
    `gem bump --no-commit #{gem_version == "" ? "" : %(--version #{gem_version})}`
  end

  release_the_new_gem_version unless is_dry_run
end

def ensure_there_is_nothing_to_commit
  status = `git status --porcelain`

  return if $CHILD_STATUS.success? && status == ""

  error = if $CHILD_STATUS.success?
            "You have uncommitted code. Please commit or stash your changes before continuing"
          else
            "You do not have Git installed. Please install Git, and commit your changes before continuing"
          end
  raise(error)
end

def object_to_boolean(value)
  [true, "true", "yes", 1, "1", "t"].include?(value.instance_of?(String) ? value.downcase : value)
end

def update_the_local_project
  puts "Pulling latest commits from remote repository"

  `git pull --rebase`
  raise "Failed in pulling latest changes from default remore repository." unless $CHILD_STATUS.success?

  `bundle install`
rescue Errno::ENOENT
  raise "Ensure you have Git and Bundler installed before continuing."
end

def release_the_new_gem_version
  puts "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"
  puts "Use the OTP for RubyGems!"
  puts "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"

  `gem release`
end
