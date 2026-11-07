# frozen_string_literal: true

require "spec_helper"
require "net/http"
require "open3"

RSpec.describe "Credentialed review app bootstrap recovery", :slow, retry: 1 do # rubocop:disable RSpec/DescribeClass
  let(:app) { dummy_test_app("bootstrap") }
  let(:cp) { Controlplane.new(Config.new([], { app: app }, [])) }
  let(:ownership) { {} }
  let(:image_digests) { {} }
  let(:revision) do
    stdout, status = Open3.capture2("git", "-C", File.expand_path("../..", __dir__), "rev-parse", "HEAD")
    raise "Cannot determine the exact source revision" unless status.success? && stdout.strip.match?(/\A[a-f0-9]{40}\z/)

    stdout.strip
  end

  def secret_name
    "#{app}-bootstrap-qa"
  end

  before do
    unless cp.fetch_gvc.nil? && cp.fetch_secret(secret_name).nil? &&
           cp.query_images(partial_gvc_match: false).fetch("items").empty?
      raise "Refusing to reuse existing bootstrap QA resources"
    end

    ownership[:owned] = true
  end

  after do
    next unless ownership[:owned] && !DummyAppSetup.skip_cleanup?

    secret = cp.fetch_secret(secret_name)
    raise "Refusing to delete an unowned QA secret" if secret && secret.dig("tags", "cpflow-bootstrap-qa") != app

    run_cpflow_command!("delete", "-a", app, "--yes")
    # A build can succeed before setup creates a GVC; delete those owned images too.
    cp.query_images(partial_gvc_match: false).fetch("items").each do |image|
      raise "Refusing to delete a foreign QA image" unless image.fetch("name").start_with?("#{app}:")

      cp.image_delete(image.fetch("name"))
    end
    cp.delete_secret(secret_name) if secret
    eventually do
      cp.fetch_gvc.nil? && cp.fetch_secret(secret_name).nil? &&
        cp.query_images(partial_gvc_match: false).fetch("items").empty?
    end
    qa_receipt("cleanup", gvc_absent: true, secret_absent: true, images_absent: true)
  end

  def eventually(timeout: 120)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return if yield
      raise "Recovery or cleanup timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 2
    end
  end

  def build_pr_image
    context = File.join(spec_directory, "dummy", "bootstrap-image")
    run_cpflow_command!("build-image", "-a", app, "--commit", revision, "--docker-context", context)
    image = run_cpflow_command!("latest-image", "-a", app).fetch(:stdout).strip
    expect(image).to match(/\A#{Regexp.escape(app)}:[0-9]+_#{revision}\z/)
    details = cp.fetch_image_details(image)
    expect(details.fetch("name")).to eq(image)
    expect(details.fetch("digest")).to match(/\Asha256:[a-f0-9]{64}\z/)
    image_digests[image] = details.fetch("digest")
    qa_receipt("built", image: image, digest: image_digests.fetch(image))
    image
  end

  def qa_receipt(phase, **details)
    receipt = { app: app, head: revision, phase: phase }.merge(details)
    LogHelpers.write_line_to_log("BOOTSTRAP_QA #{JSON.generate(receipt)}")
  end

  def refresh(image)
    run_cpflow_command!("setup-app", "-a", app, "--skip-secrets-setup", "--refresh-templates",
                        "--bootstrap-image", image)
  end

  def configured_image
    cp.fetch_workload!("rails").dig("spec", "containers", 0, "image").delete_prefix("/org/#{cp.org}/image/")
  end

  def expect_served_revision
    eventually do
      workload = cp.fetch_workload_with_status("rails")
      next false unless workload&.dig("status", "readyLatest") == true

      endpoint = workload.dig("status", "endpoint")
      next false unless endpoint

      served_revision?(endpoint)
    rescue IOError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout
      false
    end
  end

  def served_revision?(endpoint)
    uri = URI(endpoint)
    options = { use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 5 }
    response = Net::HTTP.start(uri.host, uri.port, **options) do |http|
      http.get(uri.request_uri)
    end
    response.code == "200" && response.body.strip == revision
  end

  it "recovers placeholders and preserves existing resources and valid images on subsequent refresh" do
    run_cpflow_command!("setup-app", "-a", app, "--skip-secrets-setup")
    expect(configured_image).to eq("#{app}:NO_IMAGE_AVAILABLE")
    original_gvc = cp.fetch_gvc.fetch("created")
    original_postgres = cp.fetch_workload!("postgres").slice("created", "spec")
    cp.patch_sensitive_secret_data(secret_name, "QA_VALUE" => "retain-this-fixture-value")

    failed_refresh = run_cpflow_command("setup-app", "-a", app, "--skip-secrets-setup", "--refresh-templates")
    expect(failed_refresh.fetch(:status)).not_to eq(0)
    expect(failed_refresh.fetch(:stderr)).to include("Cannot safely refresh app image")
    expect(configured_image).to eq("#{app}:NO_IMAGE_AVAILABLE")
    qa_receipt("reproduced", placeholder_retained: true)

    image = build_pr_image
    refresh(image)
    expect(configured_image).to eq(image)
    expect(cp.fetch_image_details(image).fetch("digest")).to eq(image_digests.fetch(image))
    run_cpflow_command!("deploy-image", "-a", app)
    expect_served_revision
    qa_receipt("recovered", image: configured_image, http_served_head: revision)

    newer_image = build_pr_image
    expect(newer_image).not_to eq(image)
    refresh(newer_image)
    expect(configured_image).to eq(image)
    expect(cp.fetch_gvc.fetch("created")).to eq(original_gvc)
    expect(cp.fetch_workload!("postgres").slice("created", "spec")).to eq(original_postgres)
    expect(cp.reveal_secret(secret_name, required: true).fetch("data")).to eq("QA_VALUE" => "retain-this-fixture-value")
    qa_receipt("preserved", image: configured_image, gvc_created: original_gvc,
                            backing_created: original_postgres.fetch("created"), fixture_secret_preserved: true)
  end

  it "builds an own-app PR image before creating a new app" do
    expect(cp.fetch_gvc).to be_nil
    image = build_pr_image
    expect(cp.fetch_gvc).to be_nil

    run_cpflow_command!("setup-app", "-a", app, "--skip-secrets-setup")
    expect(configured_image).to eq(image)
    run_cpflow_command!("deploy-image", "-a", app)
    expect_served_revision
    qa_receipt("fresh_app", image: configured_image, http_served_head: revision)
  end
end
