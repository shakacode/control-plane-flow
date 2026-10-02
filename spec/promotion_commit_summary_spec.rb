# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "yaml"

describe "Production promotion commit summary" do # rubocop:disable RSpec/DescribeClass
  let(:production_sha) { "a" * 40 }
  let(:staging_sha) { "b" * 40 }
  let(:release) do
    { tag_name: "production-2026-10-01-120000-1", draft: false, prerelease: false,
      published_at: "2026-10-01T12:00:00Z" }
  end
  let(:response) do
    {
      status: "ahead", ahead_by: 1, behind_by: 0,
      commits: [{ sha: staging_sha, commit: { message: "Fix checkout\n\nDetails" } }]
    }
  end

  def run_summary(staging_image:, response:, releases: [release], **options) # rubocop:disable Metrics/MethodLength
    api_status = options.fetch(:api_status, 0)
    server_url = options.fetch(:server_url, "https://github.com")
    expect_success = options.fetch(:expect_success, true)
    script = File.read(".github/actions/cpflow-preview-promotion/preview-promotion.sh")

    Dir.mktmpdir do |dir|
      File.write("#{dir}/gh", <<~BASH)
        #!/bin/sh
        test "$GH_ENTERPRISE_TOKEN" = "$GH_TOKEN" || exit 3
        printf '%s\n' "$GH_HOST" >> "$TEST_HOST_LOG"
        case "$2" in
          */releases*) printf '%s' "$TEST_RELEASES" ;;
          */commits/*) printf '%s' "$TEST_BASELINE" ;;
          */compare/*) printf '%s' "$TEST_RESPONSE"; exit "$TEST_STATUS" ;;
          *) exit 2 ;;
        esac
      BASH
      File.write("#{dir}/timeout", "#!/bin/sh\nshift\nexec \"$@\"\n")
      FileUtils.chmod(0o755, "#{dir}/timeout")
      File.write("#{dir}/cpln", "#!/bin/sh\nprintf '%s' \"$TEST_WORKLOAD\"\n")
      FileUtils.chmod(0o755, "#{dir}/cpln")
      FileUtils.chmod(0o755, "#{dir}/gh")
      env = {
        "PATH" => "#{dir}:#{ENV.fetch('PATH')}", "BASH_ENV" => "/dev/null",
        "CPLN_ORG_STAGING" => "stage", "STAGING_APP_NAME" => "app-stage", "PRIMARY_WORKLOAD" => "rails",
        "TEST_WORKLOAD" => JSON.generate(spec: { containers: [{ image: staging_image }] }),
        "TEST_RELEASES" => JSON.generate(releases),
        "TEST_BASELINE" => JSON.generate(sha: production_sha),
        "GH_TOKEN" => "fixture-token", "GH_REPO" => "example/app",
        "GITHUB_SERVER_URL" => server_url, "TEST_HOST_LOG" => "#{dir}/host",
        "GITHUB_STEP_SUMMARY" => "#{dir}/summary", "GITHUB_OUTPUT" => "#{dir}/output",
        "TEST_RESPONSE" => JSON.generate(response),
        "TEST_STATUS" => api_status.to_s
      }
      _stdout, stderr, status = Open3.capture3(env, "bash", stdin_data: script)
      expect(status.success?).to eq(expect_success), stderr
      if expect_success
        expect(File.read("#{dir}/host").lines.map(&:strip).uniq).to eq([server_url.delete_prefix("https://")])
      end
      expect(File.read("#{dir}/output")).to include("staging_image=app:main_") if expect_success
      File.exist?("#{dir}/summary") ? File.read("#{dir}/summary") : ""
    end
  end

  def summary(**overrides)
    run_summary(staging_image: "stage.registry.cpln.io/app:main_#{staging_sha}@sha256:#{'c' * 64}",
                response: response, **overrides)
  end

  it "shows the deployed image commit range and first-line commit subjects" do
    text = summary
    expect(text).to include("https://github.com/example/app/compare/#{production_sha}...#{staging_sha}")
    expect(text).to include("1 commit(s) on staging that are not in the recorded production release", "Fix checkout")
    expect(text).not_to include("Details")
  end

  it "reports no commits when the deployed images have the same SHA" do
    expect(summary(staging_image: "app:main_#{production_sha}", api_status: 1)).to include("same commit")
  end

  it "explains a missing production release without blocking promotion" do
    expect(summary(releases: [])).to include("Comparison unavailable")
  end

  it "keeps the compare link when the API cannot resolve the range" do
    expect(summary(api_status: 1)).to include("compare/", "Commit list unavailable")
  end

  it "does not block deployment when the comparison response is incomplete" do
    expect(summary(response: {})).to include("Commit list unavailable")
  end

  it "selects the most recently published production release and ignores unrelated or draft releases" do
    recent = release.merge(tag_name: "production-2026-10-02-120000-2", published_at: "2026-10-02T12:00:00Z")
    unrelated = recent.merge(tag_name: "v9.0.0", published_at: "2026-10-03T12:00:00Z")
    draft = recent.merge(tag_name: "production-2026-10-04-120000-4", draft: true)
    text = summary(releases: [unrelated, release, draft, recent])
    expect(text).to include("releases/tag/production-2026-10-02-120000-2")
    expect(text).not_to include("releases/tag/v9.0.0", "releases/tag/production-2026-10-04-120000-4")
  end

  it "uses the GitHub Enterprise host for API calls and links" do
    expect(summary(server_url: "https://github.example.com")).to include("https://github.example.com/example/app/compare/")
  end

  it "rejects staging images that have no traceable commit" do
    expect(summary(staging_image: "app:legacy", expect_success: false)).to eq("")
  end

  it "identifies diverged history instead of implying a simple forward promotion" do
    expect(summary(response: response.merge(status: "diverged", behind_by: 2))).to include("diverged", "2 commit(s)")
  end

  it "identifies staging behind production even when there are no new commits" do
    text = summary(response: response.merge(status: "behind", ahead_by: 0, behind_by: 3, commits: []))
    expect(text).to include("behind", "3 commit(s)")
    expect(text).not_to include("same commit")
  end

  it "escapes commit subjects as text in the HTML list" do
    response[:commits][0][:commit][:message] = "<script>alert(1)</script> [link](https://evil.example)"
    text = summary
    expect(text).to include("&lt;script&gt;", "[link](https://evil.example)")
    expect(text).not_to include("<script>")
  end

  it "bounds the displayed list and links the complete comparison" do
    response[:ahead_by] = 150
    response[:commits] *= 100
    text = summary
    expect(text.scan("<li>").length).to eq(100)
    expect(text).to include("Showing the first 100", "150 commit(s)")
  end
end
