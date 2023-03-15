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

  is_dry_run = Release.object_to_boolean(args_hash[:dry_run])
  gem_version = args_hash.fetch(:gem_version, "").strip
  gem_root = Release.gem_root

  Release.update_the_local_project
  Release.ensure_there_is_nothing_to_commit
  Release.sh_in_dir(gem_root,
                    "gem bump --no-commit #{gem_version == '' ? '' : %(--version #{gem_version})}")
  Release.sh_in_dir(gem_root, "bundle install")
  Release.sh_in_dir(gem_root, "git commit -am 'Bump version to #{gem_version}'")

  # See https://github.com/svenfuchs/gem-release
  Release.release_the_new_gem_version unless is_dry_run
end

module Release
  extend FileUtils
  class << self
    def gem_root
      File.expand_path("..", __dir__)
    end

    # Executes a string or an array of strings in a shell in the given directory in an unbundled environment
    def sh_in_dir(dir, *shell_commands)
      shell_commands.flatten.each { |shell_command| sh %(cd #{dir} && #{shell_command.strip}) }
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

      sh_in_dir(gem_root, "git pull --rebase")
      raise "Failed in pulling latest changes from default remore repository." unless $CHILD_STATUS.success?
    rescue Errno::ENOENT
      raise "Ensure you have Git and Bundler installed before continuing."
    end

    def release_the_new_gem_version
      puts "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"
      puts "Use the OTP for RubyGems!"
      puts "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"

      sh_in_dir(gem_root, "gem release -p")
    end
  end
end
