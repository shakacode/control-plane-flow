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
      File.write("#{repo}/missing.sh", "#!/bin/sh\n")
      File.write("#{repo}/zzz-runner", "#!/usr/bin/env bash\n")
      File.chmod(0o755, "#{repo}/zzz-runner")
      File.write("#{repo}/zzzy-crlf-runner", "#!/usr/bin/env bash\r\n")
      File.chmod(0o755, "#{repo}/zzzy-crlf-runner")
      File.write("#{repo}/zzzz-env-runner", "#!/usr/bin/env -S -iva shell -uOLD -C/tmp -P/bin FOO='x y' bash -e\n")
      File.chmod(0o755, "#{repo}/zzzz-env-runner")
      File.write("#{repo}/zzzz-env-attached-runner", "#!/usr/bin/env -S-iv bash -e\n")
      File.chmod(0o755, "#{repo}/zzzz-env-attached-runner")
      File.write("#{repo}/zzzz-env-dash-runner", "#!/usr/bin/env -S - 1=foo bash -e\n")
      File.chmod(0o755, "#{repo}/zzzz-env-dash-runner")
      File.write("#{repo}/zzzz-invalid-env-runner", "#!/usr/bin/env -S FOO=bar -i bash -e\n")
      File.chmod(0o755, "#{repo}/zzzz-invalid-env-runner")
      File.write("#{repo}/zzzz-python-runner", "#!/usr/bin/env -S FOO='x bash y' python3\n")
      File.chmod(0o755, "#{repo}/zzzz-python-runner")
      File.write("#{repo}/README.md", "```sh\necho documentation\n```\n")

      fake_bin = "#{repo}/fake-bin"
      FileUtils.mkdir_p(fake_bin)
      File.write("#{fake_bin}/shellcheck", "#!/bin/sh\nprintf '%s\\n' \"$@\"\n")
      File.chmod(0o755, "#{fake_bin}/shellcheck")

      system("git", "init", "--quiet", repo) || raise("git init failed")
      tracked_files = [
        "README.md", "aaa-missing", "aab-empty", "missing.sh", "script/check_shell_scripts", "zzz-runner",
        "zzzy-crlf-runner", "zzzz-env-attached-runner", "zzzz-env-dash-runner", "zzzz-env-runner",
        "zzzz-invalid-env-runner", "zzzz-python-runner"
      ]
      system("git", "-C", repo, "add", "--", *tracked_files) ||
        raise("git add failed")
      File.delete("#{repo}/aaa-missing")
      File.delete("#{repo}/missing.sh")

      stdout, stderr, status = Open3.capture3(
        { "PATH" => "#{fake_bin}:#{ENV.fetch('PATH')}" },
        "#{repo}/script/check_shell_scripts"
      )

      expect(status).to be_success, stderr
      expect(stdout.lines.map(&:chomp)).to eq(
        [
          "--", "script/check_shell_scripts", "zzz-runner", "zzzy-crlf-runner", "zzzz-env-attached-runner",
          "zzzz-env-dash-runner", "zzzz-env-runner"
        ]
      )
    end
  end
end
