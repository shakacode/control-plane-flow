# frozen_string_literal: true

require "spec_helper"

describe Command::RunCleanup do
  before do
    allow(ENV).to receive(:fetch).with("CPLN_ENDPOINT", "https://api.cpln.io").and_return("https://api.cpln.io")
    allow(ENV).to receive(:fetch).with("CPLN_TOKEN", nil).and_return("token")
    allow(ENV).to receive(:fetch).with("CPLN_ORG", nil).and_return(nil)
    allow(ENV).to receive(:fetch).with("CPLN_APP", nil).and_return(nil)
    allow_any_instance_of(Config).to receive(:config_file_path).and_return("spec/fixtures/config.yml") # rubocop:disable RSpec/AnyInstance

    Timecop.freeze(Time.local(2023, 5, 15))
  end

  it "displays error if 'stale_run_workload_created_days' is not set" do
    allow(Shell).to receive(:abort).with("Can't find option 'stale_run_workload_created_days' " \
                                         "for app 'my-app-other' in 'controlplane.yml'.")

    args = ["-a", "my-app-other"]
    run_command(described_class::NAME, *args)

    expect(Shell).to have_received(:abort).once
  end

  it "displays empty message", vcr: true do
    expected_output = <<~OUTPUT
      No stale run workloads found.
    OUTPUT

    args = ["-a", "my-app-staging"]
    result = run_command(described_class::NAME, *args)

    expect(result[:stderr]).to eq(expected_output)
  end

  it "lists stale run workloads", vcr: true do
    allow(Shell).to receive(:confirm).with("\nAre you sure you want to delete these 4 run workloads?")
                                     .and_return(false)

    expected_output = <<~OUTPUT
      Stale run workloads:
        rails-run-4137 (2023-05-10T12:00:00+00:00 - 4 days ago)
        rails-run-7025 (2023-05-13T00:00:00+00:00 - 2 days ago)
        rails-runner-4985 (2023-05-10T12:00:00+00:00 - 4 days ago)
        rails-runner-6669 (2023-05-13T00:00:00+00:00 - 2 days ago)
    OUTPUT

    args = ["-a", "my-app-staging"]
    result = run_command(described_class::NAME, *args)

    expect(Shell).to have_received(:confirm).once
    expect(result[:stderr]).to eq(expected_output)
  end

  it "lists stale run workloads for all apps that start with name", vcr: true do
    allow(Shell).to receive(:confirm).with("\nAre you sure you want to delete these 4 run workloads?")
                                     .and_return(false)

    expected_output = <<~OUTPUT
      Stale run workloads:
        my-app-review-1 - rails-run-1527 (2023-05-10T12:00:00+00:00 - 4 days ago)
        my-app-review-2 - rails-run-9213 (2023-05-13T00:00:00+00:00 - 2 days ago)
        my-app-review-1 - rails-runner-8931 (2023-05-10T12:00:00+00:00 - 4 days ago)
        my-app-review-2 - rails-runner-1273 (2023-05-13T00:00:00+00:00 - 2 days ago)
    OUTPUT

    args = ["-a", "my-app-review"]
    result = run_command(described_class::NAME, *args)

    expect(Shell).to have_received(:confirm).once
    expect(result[:stderr]).to eq(expected_output)
  end

  it "deletes stale run workloads", vcr: true do
    allow(Shell).to receive(:confirm).with("\nAre you sure you want to delete these 4 run workloads?")
                                     .and_return(true)

    expected_output = <<~OUTPUT
      Stale run workloads:
        rails-run-4137 (2023-05-10T12:00:00+00:00 - 4 days ago)
        rails-run-7025 (2023-05-13T00:00:00+00:00 - 2 days ago)
        rails-runner-4985 (2023-05-10T12:00:00+00:00 - 4 days ago)
        rails-runner-6669 (2023-05-13T00:00:00+00:00 - 2 days ago)

      Deleting run workload 'rails-run-4137'... done!
      Deleting run workload 'rails-run-7025'... done!
      Deleting run workload 'rails-runner-4985'... done!
      Deleting run workload 'rails-runner-6669'... done!
    OUTPUT

    args = ["-a", "my-app-staging"]
    result = run_command(described_class::NAME, *args)

    expect(Shell).to have_received(:confirm).once
    expect(result[:stderr]).to eq(expected_output)
  end

  it "deletes stale run workloads for all apps that start with name", vcr: true do
    allow(Shell).to receive(:confirm).with("\nAre you sure you want to delete these 4 run workloads?")
                                     .and_return(true)

    expected_output = <<~OUTPUT
      Stale run workloads:
        my-app-review-1 - rails-run-1527 (2023-05-10T12:00:00+00:00 - 4 days ago)
        my-app-review-2 - rails-run-9213 (2023-05-13T00:00:00+00:00 - 2 days ago)
        my-app-review-1 - rails-runner-8931 (2023-05-10T12:00:00+00:00 - 4 days ago)
        my-app-review-2 - rails-runner-1273 (2023-05-13T00:00:00+00:00 - 2 days ago)

      Deleting run workload 'my-app-review-1 - rails-run-1527'... done!
      Deleting run workload 'my-app-review-2 - rails-run-9213'... done!
      Deleting run workload 'my-app-review-1 - rails-runner-8931'... done!
      Deleting run workload 'my-app-review-2 - rails-runner-1273'... done!
    OUTPUT

    args = ["-a", "my-app-review"]
    result = run_command(described_class::NAME, *args)

    expect(Shell).to have_received(:confirm).once
    expect(result[:stderr]).to eq(expected_output)
  end

  it "skips delete confirmation", vcr: true do
    allow(Shell).to receive(:confirm)

    expected_output = <<~OUTPUT
      Stale run workloads:
        rails-run-4137 (2023-05-10T12:00:00+00:00 - 4 days ago)
        rails-run-7025 (2023-05-13T00:00:00+00:00 - 2 days ago)
        rails-runner-4985 (2023-05-10T12:00:00+00:00 - 4 days ago)
        rails-runner-6669 (2023-05-13T00:00:00+00:00 - 2 days ago)

      Deleting run workload 'rails-run-4137'... done!
      Deleting run workload 'rails-run-7025'... done!
      Deleting run workload 'rails-runner-4985'... done!
      Deleting run workload 'rails-runner-6669'... done!
    OUTPUT

    args = ["-a", "my-app-staging", "-y"]
    result = run_command(described_class::NAME, *args)

    expect(Shell).not_to have_received(:confirm)
    expect(result[:stderr]).to eq(expected_output)
  end

  it "skips delete confirmation for all apps that start with name", vcr: true do
    allow(Shell).to receive(:confirm)

    expected_output = <<~OUTPUT
      Stale run workloads:
        my-app-review-1 - rails-run-1527 (2023-05-10T12:00:00+00:00 - 4 days ago)
        my-app-review-2 - rails-run-9213 (2023-05-13T00:00:00+00:00 - 2 days ago)
        my-app-review-1 - rails-runner-8931 (2023-05-10T12:00:00+00:00 - 4 days ago)
        my-app-review-2 - rails-runner-1273 (2023-05-13T00:00:00+00:00 - 2 days ago)

      Deleting run workload 'my-app-review-1 - rails-run-1527'... done!
      Deleting run workload 'my-app-review-2 - rails-run-9213'... done!
      Deleting run workload 'my-app-review-1 - rails-runner-8931'... done!
      Deleting run workload 'my-app-review-2 - rails-runner-1273'... done!
    OUTPUT

    args = ["-a", "my-app-review", "-y"]
    result = run_command(described_class::NAME, *args)

    expect(Shell).not_to have_received(:confirm)
    expect(result[:stderr]).to eq(expected_output)
  end
end
