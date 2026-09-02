# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "open3"
require "tmpdir"

RSpec.describe "script/check_shell_scripts" do # rubocop:disable RSpec/DescribeClass
  it "passes only tracked shell surfaces to ShellCheck" do
    Dir.mktmpdir("cpflow-check-shell-scripts") do |repo|
      FileUtils.mkdir_p("#{repo}/script")
      FileUtils.cp(File.expand_path("../../script/check_shell_scripts", __dir__), "#{repo}/script/check_shell_scripts")
      File.chmod(0o755, "#{repo}/script/check_shell_scripts")

      fixtures = {
        "README.md" => "```sh\necho documentation\n```\n",
        "aab-binary" => "\0" * 65_536,
        "shell-file.sh" => "#!/bin/sh\n",
        "zzz-direct-runner" => "#!/bin/bash\t-e\n",
        "zzz-env-runner" => "#!/usr/bin/env /bin/bash -e\n",
        "zzz-env-spaced-runner" => "#!/usr/bin/env  bash\n",
        "zzz-env-tabbed-runner" => "#!/usr/bin/env\tbash\n",
        "zzz-env-short-runner" => "#!/bin/env -S bash -e\n",
        "zzz-env-long-runner" => "#!/usr/bin/env --split-string=bash -e\n",
        "zzz-python-runner" => "#!/usr/bin/env python3\n"
      }
      fixtures.each do |name, content|
        File.binwrite("#{repo}/#{name}", content)
        File.chmod(0o755, "#{repo}/#{name}") unless name.end_with?(".md", ".sh")
      end

      fake_bin = "#{repo}/fake-bin"
      FileUtils.mkdir_p(fake_bin)
      File.write("#{fake_bin}/shellcheck", "#!/bin/sh\nprintf '%s\\n' \"$@\"\n")
      File.chmod(0o755, "#{fake_bin}/shellcheck")

      system("git", "init", "--quiet", repo) || raise("git init failed")
      tracked_files = ["script/check_shell_scripts", *fixtures.keys]
      system("git", "-C", repo, "add", "--", *tracked_files) || raise("git add failed")
      stdout, stderr, status = Open3.capture3(
        { "PATH" => "#{fake_bin}:#{ENV.fetch('PATH')}" },
        "#{repo}/script/check_shell_scripts"
      )

      expect(status).to be_success, stderr
      expect(stdout.lines.map(&:chomp)).to eq(
        [
          "--", "script/check_shell_scripts", "shell-file.sh", "zzz-direct-runner", "zzz-env-long-runner",
          "zzz-env-runner", "zzz-env-short-runner", "zzz-env-spaced-runner", "zzz-env-tabbed-runner"
        ]
      )
    end
  end

  it "fails visibly for ambiguous env split shebangs" do
    Dir.mktmpdir("cpflow-check-shell-scripts") do |repo|
      FileUtils.mkdir_p("#{repo}/script")
      FileUtils.cp(File.expand_path("../../script/check_shell_scripts", __dir__), "#{repo}/script/check_shell_scripts")
      File.chmod(0o755, "#{repo}/script/check_shell_scripts")
      File.write("#{repo}/ambiguous-runner", "#!/usr/bin/env -S -i FOO=bar bash -e\n")
      File.chmod(0o755, "#{repo}/ambiguous-runner")

      fake_bin = "#{repo}/fake-bin"
      FileUtils.mkdir_p(fake_bin)
      File.write("#{fake_bin}/shellcheck", "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, "#{fake_bin}/shellcheck")

      system("git", "init", "--quiet", repo) || raise("git init failed")
      system("git", "-C", repo, "add", "--", "script/check_shell_scripts", "ambiguous-runner") ||
        raise("git add failed")

      _stdout, stderr, status = Open3.capture3(
        { "PATH" => "#{fake_bin}:#{ENV.fetch('PATH')}" },
        "#{repo}/script/check_shell_scripts"
      )

      expect(status).not_to be_success
      expect(stderr).to include("Unsupported env-prefixed shebang in tracked executable: ambiguous-runner")
    end
  end

  it "fails when a tracked executable is unreadable" do
    Dir.mktmpdir("cpflow-check-shell-scripts") do |repo|
      FileUtils.mkdir_p("#{repo}/script")
      FileUtils.cp(File.expand_path("../../script/check_shell_scripts", __dir__), "#{repo}/script/check_shell_scripts")
      File.chmod(0o755, "#{repo}/script/check_shell_scripts")
      File.write("#{repo}/missing-runner", "#!/bin/sh\n")
      File.chmod(0o755, "#{repo}/missing-runner")

      fake_bin = "#{repo}/fake-bin"
      FileUtils.mkdir_p(fake_bin)
      File.write("#{fake_bin}/shellcheck", "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, "#{fake_bin}/shellcheck")

      system("git", "init", "--quiet", repo) || raise("git init failed")
      system("git", "-C", repo, "add", "--", "script/check_shell_scripts", "missing-runner") || raise("git add failed")
      File.delete("#{repo}/missing-runner")

      _stdout, stderr, status = Open3.capture3(
        { "PATH" => "#{fake_bin}:#{ENV.fetch('PATH')}" },
        "#{repo}/script/check_shell_scripts"
      )

      expect(status).not_to be_success
      expect(stderr).to include("Tracked executable is not readable: missing-runner")
    end
  end
end
