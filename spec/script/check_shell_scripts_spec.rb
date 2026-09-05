# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "open3"
require "tmpdir"

RSpec.describe "script/check_shell_scripts" do # rubocop:disable RSpec/DescribeClass
  let(:source_script) { File.expand_path("../../script/check_shell_scripts", __dir__) }
  let(:declared_scripts) do
    %w[
      .agents/bin/docs .agents/bin/lint .agents/bin/setup .agents/bin/test .agents/bin/validate
      lib/github_flow_templates/bin/test-cpflow-github-flow
      script/check_command_docs script/check_cpln_links script/check_shell_scripts
      script/precommit/check_command_docs script/precommit/check_cpln_links
      script/precommit/check_trailing_newlines script/precommit/get_changed_files
      script/precommit/ruby_autofix script/precommit/ruby_lint spec/dummy/bin/dev
    ]
  end

  let(:repo) { Dir.mktmpdir("cpflow-check-shell-scripts") }

  after { FileUtils.remove_entry(repo) }

  before do
    system("git", "init", "--quiet", repo) || raise("git init failed")
    declared_scripts.each { |path| write_fixture(path, "#!/bin/bash\n") }
    FileUtils.cp(source_script, "#{repo}/script/check_shell_scripts")
    write_fixture("fake-bin/shellcheck", "#!/bin/sh\nprintf '%s\\0' \"$@\"\n", tracked: false)
  end

  def write_fixture(path, content, tracked: true, executable: true)
    FileUtils.mkdir_p(File.dirname("#{repo}/#{path}"))
    File.binwrite("#{repo}/#{path}", content)
    File.chmod(executable ? 0o755 : 0o644, "#{repo}/#{path}")
    return unless tracked

    system("git", "-C", repo, "add", "--", path) || raise("git add failed")
  end

  def run_scanner(root = repo)
    Open3.capture3(
      { "BASH_ENV" => "/dev/null", "PATH" => "#{repo}/fake-bin:#{ENV.fetch('PATH')}" },
      "#{root}/script/check_shell_scripts"
    )
  end

  it "selects declared entrypoints and tracked shell suffixes without interpreting other shebangs" do
    shell_paths = ["shell file.sh", "-dash.bash", "semi;colon.sh", "tab\tname.sh", "line\nname.sh"]
    shell_paths.each { |path| write_fixture(path, "#!/bin/sh\n", executable: false) }
    write_fixture(".agents/bin/docs", "#!/usr/bin/env -S -u FOO bash\n")
    write_fixture(".agents/bin/lint", "#!/usr/bin/env -S -C /tmp bash\n")
    write_fixture(".agents/bin/setup", "#!/usr/bin/env FOO=bar sh\n")
    write_fixture(".agents/bin/test", "#!/usr/bin/env -S -S \"bash -e\"\n")
    write_fixture("README.md", "```sh\necho documentation\n```\n")
    write_fixture("directory.sh/non-shell.rb", "#!/usr/bin/env ruby\n")
    write_fixture("binary", "\0" * 65_536)
    write_fixture("unlisted-shell", "#!/bin/bash\n")
    write_fixture("python-runner", "#!/usr/bin/env -S -u FOO python3\n")
    write_fixture("ruby-runner", "#!/usr/bin/env RUBYOPT=-W0 ruby\n")
    write_fixture("untracked.sh", "#!/bin/sh\n", tracked: false)

    stdout, stderr, status = run_scanner

    expect(status).to be_success, stderr
    expect(stdout.split("\0")).to eq(["--", *(declared_scripts + shell_paths).sort])
  end

  it "preserves all 23 current repository shell surfaces" do
    suffix_scripts = %w[
      .github/actions/cpflow-delete-control-plane-app/delete-app.sh
      lib/generator_templates/entrypoint.sh lib/generator_templates/release_script.sh
      lib/generator_templates_sqlite/release_script.sh
      spec/dummy/.controlplane/entrypoint.sh spec/dummy/.controlplane/release-invalid.sh
      spec/dummy/.controlplane/release.sh
    ]

    stdout, stderr, status = run_scanner(File.expand_path("..", File.dirname(source_script)))

    expect(status).to be_success, stderr
    expect(stdout.split("\0")).to eq(["--", *(declared_scripts + suffix_scripts).sort])
  end

  it "fails when a declared extensionless entrypoint is no longer tracked" do
    system("git", "-C", repo, "rm", "--cached", "--quiet", "--", ".agents/bin/docs") || raise("git rm failed")

    stdout, stderr, status = run_scanner

    expect(status).not_to be_success
    expect(stdout).to be_empty
    expect(stderr).to include("Declared extensionless shell scripts must be tracked")
  end

  it "does not mistake a directory's tracked children for a declared entrypoint" do
    File.delete("#{repo}/.agents/bin/docs")
    write_fixture(".agents/bin/docs/other.sh", "#!/bin/sh\n")
    system("git", "-C", repo, "add", "--all", "--", ".agents/bin/docs") || raise("git add failed")

    stdout, stderr, status = run_scanner

    expect(status).not_to be_success
    expect(stdout).to be_empty
    expect(stderr).to include("Declared shell entrypoint is not a readable file: .agents/bin/docs")
  end

  it "fails on Git inventory errors even after partial output" do
    write_fixture("fake-bin/git", <<~SH, tracked: false)
      #!/bin/sh
      if [ "$2" = "-z" ]; then
        printf 'script/check_shell_scripts\\0'
        exit 42
      fi
      exit 0
    SH

    stdout, stderr, status = run_scanner

    expect(status).not_to be_success
    expect(stdout).to be_empty
    expect(stderr).to include("Unable to read tracked shell inventory")
  end

  [".agents/bin/docs", "missing-script.sh"].each do |path|
    it "fails when a selected file is missing: #{path}" do
      write_fixture(path, "#!/bin/sh\n")
      File.delete("#{repo}/#{path}")

      stdout, stderr, status = run_scanner

      expect(status).not_to be_success
      expect(stdout).to be_empty
      expect(stderr).to include("Tracked shell script is not readable: #{path}")
    end

    it "fails when a selected file is unreadable: #{path}" do
      write_fixture(path, "#!/bin/sh\n")
      File.chmod(0o000, "#{repo}/#{path}")

      stdout, stderr, status = run_scanner

      expect(status).not_to be_success
      expect(stdout).to be_empty
      expect(stderr).to include("Tracked shell script is not readable: #{path}")
    end
  end

  it "fails when Git returns an empty selection" do
    write_fixture("fake-bin/git", "#!/bin/sh\nexit 0\n", tracked: false)

    stdout, stderr, status = run_scanner

    expect(status).not_to be_success
    expect(stdout).to be_empty
    expect(stderr).to include("No tracked shell scripts found")
  end

  it "preserves ShellCheck's failure status" do
    write_fixture("fake-bin/shellcheck", "#!/bin/sh\nexit 7\n", tracked: false)

    _stdout, _stderr, status = run_scanner

    expect(status.exitstatus).to eq(7)
  end
end
