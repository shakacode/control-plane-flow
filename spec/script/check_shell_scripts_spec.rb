# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "open3"
require "tmpdir"

RSpec.describe "script/check_shell_scripts" do # rubocop:disable RSpec/DescribeClass
  it "ignores unreadable and empty executable candidates while discovering shell scripts" do
    Dir.mktmpdir("cpflow-check-shell-scripts") do |repo|
      FileUtils.mkdir_p("#{repo}/script")
      FileUtils.cp(File.expand_path("../../script/check_shell_scripts", __dir__), "#{repo}/script/check_shell_scripts")
      File.chmod(0o755, "#{repo}/script/check_shell_scripts")

      File.write("#{repo}/aaa-missing", "not a shell script\n")
      File.chmod(0o755, "#{repo}/aaa-missing")
      File.write("#{repo}/aab-empty", "")
      File.chmod(0o755, "#{repo}/aab-empty")
      File.write("#{repo}/zzz-runner", "#!/usr/bin/env bash\n")
      File.chmod(0o755, "#{repo}/zzz-runner")
      File.write("#{repo}/zzzz-env-runner", "#!/usr/bin/env -S bash -e\n")
      File.chmod(0o755, "#{repo}/zzzz-env-runner")
      File.write("#{repo}/README.md", "```sh\necho documentation\n```\n")

      fake_bin = "#{repo}/fake-bin"
      FileUtils.mkdir_p(fake_bin)
      File.write("#{fake_bin}/shellcheck", "#!/bin/sh\nprintf '%s\\n' \"$@\"\n")
      File.chmod(0o755, "#{fake_bin}/shellcheck")

      system("git", "init", "--quiet", repo) || raise("git init failed")
      tracked_files = [
        "README.md", "aaa-missing", "aab-empty", "script/check_shell_scripts", "zzz-runner", "zzzz-env-runner"
      ]
      system("git", "-C", repo, "add", "--", *tracked_files) ||
        raise("git add failed")
      File.delete("#{repo}/aaa-missing")

      stdout, stderr, status = Open3.capture3(
        { "PATH" => "#{fake_bin}:#{ENV.fetch('PATH')}" },
        "#{repo}/script/check_shell_scripts"
      )

      expect(status).to be_success, stderr
      expect(stdout.lines.map(&:chomp)).to eq(
        ["--", "script/check_shell_scripts", "zzz-runner", "zzzz-env-runner"]
      )
    end
  end
end
