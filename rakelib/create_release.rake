# frozen_string_literal: true

require "English"
require "rake/file_utils"

desc("Releases the gem package using the given version.

  IMPORTANT: the gem version must be in valid rubygem format (no dashes).
  This task depends on the gem-release ruby gem.

  1st argument: The new version in rubygem format (no dashes). Pass no argument to
                automatically perform a patch version bump.
  2nd argument: Perform a dry run by passing 'true' as a second argument.

  Example: `rake release[2.1.0,false]`")

task :create_release, %i[gem_version dry_run] do |_t, args|
  ensure_changes_are_committed

  args_hash = args.to_hash

  is_dry_run = object_to_boolean(args_hash[:dry_run])
  gem_version = args_hash.fetch(:gem_version, "").strip
  gem_root = File.expand_path("..", __dir__)

  Dir.chdir(gem_root) { prepare_for_release(gem_version) }

  release_the_new_gem_version unless is_dry_run
end

def ensure_changes_are_committed
  status = `git status --porcelain`
  return if status == ""

  raise "You have uncommitted code. Please commit or stash your changes before continuing"
rescue Errno::ENOENT
  raise "You do not have Git installed. Please install Git, and commit your changes before continuing"
end

def object_to_boolean(value)
  [true, "true", "yes", 1, "1", "t"].include?(value.instance_of?(String) ? value.downcase : value)
end

def prepare_for_release(gem_version)
  # See https://github.com/svenfuchs/gem-release
  `git pull --rebase`
  `gem bump --no-commit #{gem_version == "" ? "" : %(--version #{gem_version})}`
  `bundle install`
end

def release_the_new_gem_version
  puts "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"
  puts "Use the OTP for RubyGems!"
  puts "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"
  `gem release`
end
