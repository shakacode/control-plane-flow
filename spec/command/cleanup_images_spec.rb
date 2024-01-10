# frozen_string_literal: true

require "spec_helper"

describe Command::CleanupImages do
  before do
    allow(ENV).to receive(:fetch).with("CPLN_ENDPOINT", "https://api.cpln.io").and_return("https://api.cpln.io")
    allow(ENV).to receive(:fetch).with("CPLN_TOKEN", nil).and_return("token")
    allow(ENV).to receive(:fetch).with("CPLN_ORG", nil).and_return(nil)
    allow(ENV).to receive(:fetch).with("CPLN_APP", nil).and_return(nil)
    allow_any_instance_of(Config).to receive(:config_file_path).and_return("spec/fixtures/config.yml") # rubocop:disable RSpec/AnyInstance

    Timecop.freeze(Time.local(2023, 8, 23))
  end

  it "displays error if 'image_retention_max_qty' and 'image_retention_days' are not set" do
    allow(Shell).to receive(:abort).with("Can't find either option 'image_retention_max_qty' " \
                                         "or 'image_retention_days' for app 'my-app-test-1' in 'controlplane.yml'.")

    args = ["-a", "my-app-test-1"]
    run_command(described_class::NAME, *args)

    expect(Shell).to have_received(:abort).once
  end

  it "displays empty message", vcr: true do
    expected_output = <<~OUTPUT
      No images to delete.
    OUTPUT

    args = ["-a", "my-app-test-2"]
    result = run_command(described_class::NAME, *args)

    expect(result[:stderr]).to eq(expected_output)
  end

  it "lists images to delete based on max quantity and days", vcr: true do
    allow(Shell).to receive(:confirm).with("\nAre you sure you want to delete these 6 images?")
                                     .and_return(false)

    expected_output = <<~OUTPUT
      Images to delete:
        - my-app-test-3:508_149ba15 (2023-08-02T08:35:20+00:00 - exceeds max quantity of 15)
        - my-app-test-3:509_1ddaddb (2023-08-03T08:50:12+00:00 - exceeds max quantity of 15)
        - my-app-test-3:510_ad671e6 (2023-08-04T01:17:29+00:00 - exceeds max quantity of 15)
        - my-app-test-3:511_7ef99dd (2023-08-05T02:51:14+00:00 - older than 15 days)
        - my-app-test-3:512_346384f (2023-08-06T03:08:27+00:00 - older than 15 days)
        - my-app-test-3:513_ec7930a (2023-08-07T13:20:18+00:00 - older than 15 days)
    OUTPUT

    args = ["-a", "my-app-test-3"]
    result = run_command(described_class::NAME, *args)

    expect(Shell).to have_received(:confirm).once
    expect(result[:stderr]).to eq(expected_output)
  end

  it "lists images to delete based on max quantity", vcr: true do
    allow(Shell).to receive(:confirm).with("\nAre you sure you want to delete these 6 images?")
                                     .and_return(false)

    expected_output = <<~OUTPUT
      Images to delete:
        - my-app-test-4:508_149ba15 (2023-08-02T08:35:20+00:00 - exceeds max quantity of 12)
        - my-app-test-4:509_1ddaddb (2023-08-03T08:50:12+00:00 - exceeds max quantity of 12)
        - my-app-test-4:510_ad671e6 (2023-08-04T01:17:29+00:00 - exceeds max quantity of 12)
        - my-app-test-4:511_7ef99dd (2023-08-05T02:51:14+00:00 - exceeds max quantity of 12)
        - my-app-test-4:512_346384f (2023-08-06T03:08:27+00:00 - exceeds max quantity of 12)
        - my-app-test-4:513_ec7930a (2023-08-07T13:20:18+00:00 - exceeds max quantity of 12)
    OUTPUT

    args = ["-a", "my-app-test-4"]
    result = run_command(described_class::NAME, *args)

    expect(Shell).to have_received(:confirm).once
    expect(result[:stderr]).to eq(expected_output)
  end

  it "lists images to delete based on days", vcr: true do
    allow(Shell).to receive(:confirm).with("\nAre you sure you want to delete these 6 images?")
                                     .and_return(false)

    expected_output = <<~OUTPUT
      Images to delete:
        - my-app-test-5:508_149ba15 (2023-08-02T08:35:20+00:00 - older than 12 days)
        - my-app-test-5:509_1ddaddb (2023-08-03T08:50:12+00:00 - older than 12 days)
        - my-app-test-5:510_ad671e6 (2023-08-04T01:17:29+00:00 - older than 12 days)
        - my-app-test-5:511_7ef99dd (2023-08-05T02:51:14+00:00 - older than 12 days)
        - my-app-test-5:512_346384f (2023-08-06T03:08:27+00:00 - older than 12 days)
        - my-app-test-5:513_ec7930a (2023-08-07T13:20:18+00:00 - older than 12 days)
    OUTPUT

    args = ["-a", "my-app-test-5"]
    result = run_command(described_class::NAME, *args)

    expect(Shell).to have_received(:confirm).once
    expect(result[:stderr]).to eq(expected_output)
  end

  it "deletes images", vcr: true do
    allow(Shell).to receive(:confirm).with("\nAre you sure you want to delete these 6 images?")
                                     .and_return(true)

    expected_output = <<~OUTPUT
      Images to delete:
        - my-app-test-3:508_149ba15 (2023-08-02T08:35:20+00:00 - exceeds max quantity of 15)
        - my-app-test-3:509_1ddaddb (2023-08-03T08:50:12+00:00 - exceeds max quantity of 15)
        - my-app-test-3:510_ad671e6 (2023-08-04T01:17:29+00:00 - exceeds max quantity of 15)
        - my-app-test-3:511_7ef99dd (2023-08-05T02:51:14+00:00 - older than 15 days)
        - my-app-test-3:512_346384f (2023-08-06T03:08:27+00:00 - older than 15 days)
        - my-app-test-3:513_ec7930a (2023-08-07T13:20:18+00:00 - older than 15 days)

      Deleting image 'my-app-test-3:508_149ba15'... done!
      Deleting image 'my-app-test-3:509_1ddaddb'... done!
      Deleting image 'my-app-test-3:510_ad671e6'... done!
      Deleting image 'my-app-test-3:511_7ef99dd'... done!
      Deleting image 'my-app-test-3:512_346384f'... done!
      Deleting image 'my-app-test-3:513_ec7930a'... done!
    OUTPUT

    args = ["-a", "my-app-test-3"]
    result = run_command(described_class::NAME, *args)

    expect(Shell).to have_received(:confirm).once
    expect(result[:stderr]).to eq(expected_output)
  end

  it "skips delete confirmation", vcr: true do
    allow(Shell).to receive(:confirm)

    expected_output = <<~OUTPUT
      Images to delete:
        - my-app-test-3:508_149ba15 (2023-08-02T08:35:20+00:00 - exceeds max quantity of 15)
        - my-app-test-3:509_1ddaddb (2023-08-03T08:50:12+00:00 - exceeds max quantity of 15)
        - my-app-test-3:510_ad671e6 (2023-08-04T01:17:29+00:00 - exceeds max quantity of 15)
        - my-app-test-3:511_7ef99dd (2023-08-05T02:51:14+00:00 - older than 15 days)
        - my-app-test-3:512_346384f (2023-08-06T03:08:27+00:00 - older than 15 days)
        - my-app-test-3:513_ec7930a (2023-08-07T13:20:18+00:00 - older than 15 days)

      Deleting image 'my-app-test-3:508_149ba15'... done!
      Deleting image 'my-app-test-3:509_1ddaddb'... done!
      Deleting image 'my-app-test-3:510_ad671e6'... done!
      Deleting image 'my-app-test-3:511_7ef99dd'... done!
      Deleting image 'my-app-test-3:512_346384f'... done!
      Deleting image 'my-app-test-3:513_ec7930a'... done!
    OUTPUT

    args = ["-a", "my-app-test-3", "-y"]
    result = run_command(described_class::NAME, *args)

    expect(Shell).not_to have_received(:confirm)
    expect(result[:stderr]).to eq(expected_output)
  end
end
