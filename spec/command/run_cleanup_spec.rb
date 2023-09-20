# frozen_string_literal: true

require "spec_helper"

describe Command::RunCleanup do
  before do
    allow(ENV).to receive(:fetch).with("CPLN_ENDPOINT", "https://api.cpln.io").and_return("https://api.cpln.io")
    allow(ENV).to receive(:fetch).with("CPLN_TOKEN", nil).and_return("token")
    allow_any_instance_of(Config).to receive(:find_app_config_file).and_return("spec/fixtures/config.yml") # rubocop:disable RSpec/AnyInstance

    Timecop.freeze(Time.local(2023, 5, 15))
  end

  it "displays error if 'stale_run_workload_created_days' is not set" do
    allow(Shell).to receive(:abort).with("Can't find option 'stale_run_workload_created_days' " \
                                         "for app 'my-app-other' in 'controlplane.yml'.")

    args = ["-a", "my-app-other"]
    Cpl::Cli.start([described_class::NAME, *args])

    expect(Shell).to have_received(:abort).once
  end

  it "displays empty message", vcr: true do
    expected_output = <<~OUTPUT
      No stale run workloads found.
    OUTPUT

    output = command_output do
      args = ["-a", "my-app-staging"]
      Cpl::Cli.start([described_class::NAME, *args])
    end

    expect(output).to eq(expected_output)
  end

  it "lists stale run workloads", vcr: true do
    allow(Shell).to receive(:confirm).with("\nAre you sure you want to delete these 4 run workloads?")
                                     .and_return(false)

    expected_output = <<~OUTPUT
      Stale run workloads:
        rails-run-4137 (#{Shell.color('2023-05-10T12:00:00+00:00 - 4 days ago', :red)})
        rails-run-7025 (#{Shell.color('2023-05-13T00:00:00+00:00 - 2 days ago', :red)})
        rails-runner-4985 (#{Shell.color('2023-05-10T12:00:00+00:00 - 4 days ago', :red)})
        rails-runner-6669 (#{Shell.color('2023-05-13T00:00:00+00:00 - 2 days ago', :red)})
    OUTPUT

    output = command_output do
      args = ["-a", "my-app-staging"]
      Cpl::Cli.start([described_class::NAME, *args])
    end

    expect(Shell).to have_received(:confirm).once
    expect(output).to eq(expected_output)
  end

  it "lists stale run workloads for all apps that start with name", vcr: true do
    allow(Shell).to receive(:confirm).with("\nAre you sure you want to delete these 4 run workloads?")
                                     .and_return(false)

    expected_output = <<~OUTPUT
      Stale run workloads:
        my-app-review-1 - rails-run-1527 (#{Shell.color('2023-05-10T12:00:00+00:00 - 4 days ago', :red)})
        my-app-review-2 - rails-run-9213 (#{Shell.color('2023-05-13T00:00:00+00:00 - 2 days ago', :red)})
        my-app-review-1 - rails-runner-8931 (#{Shell.color('2023-05-10T12:00:00+00:00 - 4 days ago', :red)})
        my-app-review-2 - rails-runner-1273 (#{Shell.color('2023-05-13T00:00:00+00:00 - 2 days ago', :red)})
    OUTPUT

    output = command_output do
      args = ["-a", "my-app-review"]
      Cpl::Cli.start([described_class::NAME, *args])
    end

    expect(Shell).to have_received(:confirm).once
    expect(output).to eq(expected_output)
  end

  it "deletes stale run workloads", vcr: true do
    allow(Shell).to receive(:confirm).with("\nAre you sure you want to delete these 4 run workloads?")
                                     .and_return(true)

    expected_output = <<~OUTPUT
      Stale run workloads:
        rails-run-4137 (#{Shell.color('2023-05-10T12:00:00+00:00 - 4 days ago', :red)})
        rails-run-7025 (#{Shell.color('2023-05-13T00:00:00+00:00 - 2 days ago', :red)})
        rails-runner-4985 (#{Shell.color('2023-05-10T12:00:00+00:00 - 4 days ago', :red)})
        rails-runner-6669 (#{Shell.color('2023-05-13T00:00:00+00:00 - 2 days ago', :red)})

      Deleting run workload 'rails-run-4137'... #{Shell.color('done!', :green)}
      Deleting run workload 'rails-run-7025'... #{Shell.color('done!', :green)}
      Deleting run workload 'rails-runner-4985'... #{Shell.color('done!', :green)}
      Deleting run workload 'rails-runner-6669'... #{Shell.color('done!', :green)}
    OUTPUT

    output = command_output do
      args = ["-a", "my-app-staging"]
      Cpl::Cli.start([described_class::NAME, *args])
    end

    expect(Shell).to have_received(:confirm).once
    expect(output).to eq(expected_output)
  end

  it "deletes stale run workloads for all apps that start with name", vcr: true do
    allow(Shell).to receive(:confirm).with("\nAre you sure you want to delete these 4 run workloads?")
                                     .and_return(true)

    expected_output = <<~OUTPUT
      Stale run workloads:
        my-app-review-1 - rails-run-1527 (#{Shell.color('2023-05-10T12:00:00+00:00 - 4 days ago', :red)})
        my-app-review-2 - rails-run-9213 (#{Shell.color('2023-05-13T00:00:00+00:00 - 2 days ago', :red)})
        my-app-review-1 - rails-runner-8931 (#{Shell.color('2023-05-10T12:00:00+00:00 - 4 days ago', :red)})
        my-app-review-2 - rails-runner-1273 (#{Shell.color('2023-05-13T00:00:00+00:00 - 2 days ago', :red)})

      Deleting run workload 'my-app-review-1 - rails-run-1527'... #{Shell.color('done!', :green)}
      Deleting run workload 'my-app-review-2 - rails-run-9213'... #{Shell.color('done!', :green)}
      Deleting run workload 'my-app-review-1 - rails-runner-8931'... #{Shell.color('done!', :green)}
      Deleting run workload 'my-app-review-2 - rails-runner-1273'... #{Shell.color('done!', :green)}
    OUTPUT

    output = command_output do
      args = ["-a", "my-app-review"]
      Cpl::Cli.start([described_class::NAME, *args])
    end

    expect(Shell).to have_received(:confirm).once
    expect(output).to eq(expected_output)
  end

  it "skips delete confirmation", vcr: true do
    allow(Shell).to receive(:confirm)

    expected_output = <<~OUTPUT
      Stale run workloads:
        rails-run-4137 (#{Shell.color('2023-05-10T12:00:00+00:00 - 4 days ago', :red)})
        rails-run-7025 (#{Shell.color('2023-05-13T00:00:00+00:00 - 2 days ago', :red)})
        rails-runner-4985 (#{Shell.color('2023-05-10T12:00:00+00:00 - 4 days ago', :red)})
        rails-runner-6669 (#{Shell.color('2023-05-13T00:00:00+00:00 - 2 days ago', :red)})

      Deleting run workload 'rails-run-4137'... #{Shell.color('done!', :green)}
      Deleting run workload 'rails-run-7025'... #{Shell.color('done!', :green)}
      Deleting run workload 'rails-runner-4985'... #{Shell.color('done!', :green)}
      Deleting run workload 'rails-runner-6669'... #{Shell.color('done!', :green)}
    OUTPUT

    output = command_output do
      args = ["-a", "my-app-staging", "-y"]
      Cpl::Cli.start([described_class::NAME, *args])
    end

    expect(Shell).not_to have_received(:confirm)
    expect(output).to eq(expected_output)
  end

  it "skips delete confirmation for all apps that start with name", vcr: true do
    allow(Shell).to receive(:confirm)

    expected_output = <<~OUTPUT
      Stale run workloads:
        my-app-review-1 - rails-run-1527 (#{Shell.color('2023-05-10T12:00:00+00:00 - 4 days ago', :red)})
        my-app-review-2 - rails-run-9213 (#{Shell.color('2023-05-13T00:00:00+00:00 - 2 days ago', :red)})
        my-app-review-1 - rails-runner-8931 (#{Shell.color('2023-05-10T12:00:00+00:00 - 4 days ago', :red)})
        my-app-review-2 - rails-runner-1273 (#{Shell.color('2023-05-13T00:00:00+00:00 - 2 days ago', :red)})

      Deleting run workload 'my-app-review-1 - rails-run-1527'... #{Shell.color('done!', :green)}
      Deleting run workload 'my-app-review-2 - rails-run-9213'... #{Shell.color('done!', :green)}
      Deleting run workload 'my-app-review-1 - rails-runner-8931'... #{Shell.color('done!', :green)}
      Deleting run workload 'my-app-review-2 - rails-runner-1273'... #{Shell.color('done!', :green)}
    OUTPUT

    output = command_output do
      args = ["-a", "my-app-review", "-y"]
      Cpl::Cli.start([described_class::NAME, *args])
    end

    expect(Shell).not_to have_received(:confirm)
    expect(output).to eq(expected_output)
  end
end
