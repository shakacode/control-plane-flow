# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"

RSpec.describe "Dummy app entrypoint" do # rubocop:disable RSpec/DescribeClass
  let(:entrypoint) { File.expand_path("../dummy/.controlplane/entrypoint.sh", __dir__) }
  let(:database_url) { "postgresql://postgres:secret-password@postgres:5432/not_created_yet" }

  let(:directory) { Dir.mktmpdir("dummy-entrypoint") }

  after { FileUtils.remove_entry(directory) }

  def executable(name, body)
    path = File.join(directory, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
    path
  end

  before do
    # Exercise Bundler setup without loading the repository's unrelated gems.
    File.write(File.join(directory, "Gemfile"), "")
    # Keep the old TCP probe runnable too, so it fails the readiness assertion.
    %w[grep sed].each { |name| File.symlink("/usr/bin/#{name}", File.join(directory, name)) }
    executable("curl", 'echo "curl: (52) Empty reply from server" >&2; exit 52')
    executable("sleep", 'echo sleep >> "$EVENTS"')
    executable("ruby", <<~'SH')
      printf '%s\n' "$@" >> "$PROBE_ARGS"
      exec "$REAL_RUBY" "$@"
    SH
    File.write(File.join(directory, "pg.rb"), <<~'RUBY')
      require "json"
      module PG
        class Connection
          def self.ping(url, **options)
            File.open(ENV.fetch("PING_ARGS"), "a") { |file| file.puts JSON.generate([url, options]) }
            count_file = ENV.fetch("COUNT")
            count = (File.exist?(count_file) ? File.read(count_file).to_i : 0) + 1
            File.write(count_file, count)
            File.open(ENV.fetch("EVENTS"), "a") { |file| file.puts "probe" }
            return 0 if count >= ENV.fetch("READY_AFTER").to_i

            warn "connection failed: #{url}"
            ENV.fetch("PROBE_STATUS").to_i
          end
        end
      end
    RUBY
    executable("hook", <<~'SH')
      echo hook >> "$EVENTS"
      printf '<%s>\n' "$@"
      exit "$HOOK_STATUS"
    SH
  end

  def run_entrypoint(ready_after: 3, hook_status: 0, probe_status: 2, missing_probe: false)
    File.unlink(File.join(directory, "ruby")) if missing_probe
    environment = {
      "PATH" => directory, "DATABASE_URL" => database_url, "BUNDLE_GEMFILE" => File.join(directory, "Gemfile"),
      "REAL_RUBY" => RbConfig.ruby, "RUBYLIB" => directory, "PING_ARGS" => File.join(directory, "ping-args"),
      "EVENTS" => File.join(directory, "events"), "COUNT" => File.join(directory, "count"),
      "PROBE_ARGS" => File.join(directory, "probe-args"), "READY_AFTER" => ready_after.to_s,
      "HOOK_STATUS" => hook_status.to_s, "PROBE_STATUS" => probe_status.to_s
    }
    Open3.capture3(environment, "/bin/sh", entrypoint, File.join(directory, "hook"),
                   "argument with spaces", "*", unsetenv_others: true)
  end

  it "waits for PostgreSQL instead of starting the hook after an empty TCP reply" do
    stdout, stderr, status = run_entrypoint

    expect(status).to be_success
    expect(File.readlines(File.join(directory, "events"), chomp: true))
      .to eq(%w[probe sleep probe sleep probe hook])
    expect(stdout).to include("<argument with spaces>\n<*>\n")
    expect(stdout + stderr).not_to include("secret-password")
    expect(File.readlines(File.join(directory, "ping-args"), chomp: true).map { |line| JSON.parse(line) })
      .to eq([[database_url, { "connect_timeout" => 3 }]] * 3)
  end

  it "retries a server rejecting connections and propagates an invalid hook's failure without retrying it" do
    _stdout, _stderr, status = run_entrypoint(ready_after: 2, probe_status: 1, hook_status: 64)

    expect(status.exitstatus).to eq(64)
    expect(File.readlines(File.join(directory, "events"), chomp: true)).to eq(%w[probe sleep probe hook])
  end

  it "keeps database credentials out of the readiness process arguments" do
    stdout, stderr, status = run_entrypoint(ready_after: 1)

    expect(status).to be_success
    expect(File.read(File.join(directory, "probe-args"))).not_to include("secret-password")
    expect(stdout + stderr).not_to include("secret-password")
  end

  it "fails after bounded probes without executing the hook or exposing credentials" do
    stdout, stderr, status = run_entrypoint(ready_after: 100)

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include("PostgreSQL did not become ready after 60 attempts")
    expect(stdout + stderr).not_to include("secret-password")
    expect(File.readlines(File.join(directory, "events"), chomp: true)).to eq((%w[probe sleep] * 59) + ["probe"])
  end

  it "fails immediately for an invalid readiness configuration without exposing credentials" do
    stdout, stderr, status = run_entrypoint(probe_status: 3)

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include("check DATABASE_URL and the Ruby pg gem")
    expect(stdout + stderr).not_to include("secret-password")
    expect(File.readlines(File.join(directory, "events"), chomp: true)).to eq(["probe"])
  end

  it "fails with installation guidance when Ruby is missing" do
    _stdout, stderr, status = run_entrypoint(missing_probe: true)

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include("Ruby and the pg gem are required")
    expect(File.exist?(File.join(directory, "events"))).to be(false)
  end

  it "fails without retrying or leaking credentials when the pg gem cannot load" do
    File.write(File.join(directory, "pg.rb"), 'raise LoadError, ENV.fetch("DATABASE_URL")')
    stdout, stderr, status = run_entrypoint

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include("check DATABASE_URL and the Ruby pg gem")
    expect(stdout + stderr).not_to include("secret-password")
    expect(File.exist?(File.join(directory, "events"))).to be(false)
  end

  [nil, ""].each do |url|
    context "when DATABASE_URL is #{url.inspect}" do
      let(:database_url) { url }

      it "rejects missing configuration instead of probing a default local database" do
        _stdout, stderr, status = run_entrypoint(ready_after: 1)

        expect(status.exitstatus).to eq(1)
        expect(stderr).to include("DATABASE_URL must be set")
        expect(File.exist?(File.join(directory, "events"))).to be(false)
      end
    end
  end
end
