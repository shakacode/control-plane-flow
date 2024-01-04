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
    Cpl::Cli.start([described_class::NAME, *args])

    expect(Shell).to have_received(:abort).once
  end

  it "displays empty message", vcr: true do
    expected_output = <<~OUTPUT
      No images to delete.
    OUTPUT

    output = command_output do
      args = ["-a", "my-app-test-2"]
      Cpl::Cli.start([described_class::NAME, *args])
    end

    expect(output).to eq(expected_output)
  end

  it "lists images to delete based on max quantity and days", vcr: true do
    allow(Shell).to receive(:confirm).with("\nAre you sure you want to delete these 6 images?")
                                     .and_return(false)

    expected_output = <<~OUTPUT
      Images to delete:
        - my-app-test-3:508_149ba15 (#{Shell.color('2023-08-02T08:35:20+00:00', :red)} - #{Shell.color('exceeds max quantity of 15', :red)})
        - my-app-test-3:509_1ddaddb (#{Shell.color('2023-08-03T08:50:12+00:00', :red)} - #{Shell.color('exceeds max quantity of 15', :red)})
        - my-app-test-3:510_ad671e6 (#{Shell.color('2023-08-04T01:17:29+00:00', :red)} - #{Shell.color('exceeds max quantity of 15', :red)})
        - my-app-test-3:511_7ef99dd (#{Shell.color('2023-08-05T02:51:14+00:00', :red)} - #{Shell.color('older than 15 days', :red)})
        - my-app-test-3:512_346384f (#{Shell.color('2023-08-06T03:08:27+00:00', :red)} - #{Shell.color('older than 15 days', :red)})
        - my-app-test-3:513_ec7930a (#{Shell.color('2023-08-07T13:20:18+00:00', :red)} - #{Shell.color('older than 15 days', :red)})
    OUTPUT

    output = command_output do
      args = ["-a", "my-app-test-3"]
      Cpl::Cli.start([described_class::NAME, *args])
    end

    expect(Shell).to have_received(:confirm).once
    expect(output).to eq(expected_output)
  end

  it "lists images to delete based on max quantity", vcr: true do
    allow(Shell).to receive(:confirm).with("\nAre you sure you want to delete these 6 images?")
                                     .and_return(false)

    expected_output = <<~OUTPUT
      Images to delete:
        - my-app-test-4:508_149ba15 (#{Shell.color('2023-08-02T08:35:20+00:00', :red)} - #{Shell.color('exceeds max quantity of 12', :red)})
        - my-app-test-4:509_1ddaddb (#{Shell.color('2023-08-03T08:50:12+00:00', :red)} - #{Shell.color('exceeds max quantity of 12', :red)})
        - my-app-test-4:510_ad671e6 (#{Shell.color('2023-08-04T01:17:29+00:00', :red)} - #{Shell.color('exceeds max quantity of 12', :red)})
        - my-app-test-4:511_7ef99dd (#{Shell.color('2023-08-05T02:51:14+00:00', :red)} - #{Shell.color('exceeds max quantity of 12', :red)})
        - my-app-test-4:512_346384f (#{Shell.color('2023-08-06T03:08:27+00:00', :red)} - #{Shell.color('exceeds max quantity of 12', :red)})
        - my-app-test-4:513_ec7930a (#{Shell.color('2023-08-07T13:20:18+00:00', :red)} - #{Shell.color('exceeds max quantity of 12', :red)})
    OUTPUT

    output = command_output do
      args = ["-a", "my-app-test-4"]
      Cpl::Cli.start([described_class::NAME, *args])
    end

    expect(Shell).to have_received(:confirm).once
    expect(output).to eq(expected_output)
  end

  it "lists images to delete based on days", vcr: true do
    allow(Shell).to receive(:confirm).with("\nAre you sure you want to delete these 6 images?")
                                     .and_return(false)

    expected_output = <<~OUTPUT
      Images to delete:
        - my-app-test-5:508_149ba15 (#{Shell.color('2023-08-02T08:35:20+00:00', :red)} - #{Shell.color('older than 12 days', :red)})
        - my-app-test-5:509_1ddaddb (#{Shell.color('2023-08-03T08:50:12+00:00', :red)} - #{Shell.color('older than 12 days', :red)})
        - my-app-test-5:510_ad671e6 (#{Shell.color('2023-08-04T01:17:29+00:00', :red)} - #{Shell.color('older than 12 days', :red)})
        - my-app-test-5:511_7ef99dd (#{Shell.color('2023-08-05T02:51:14+00:00', :red)} - #{Shell.color('older than 12 days', :red)})
        - my-app-test-5:512_346384f (#{Shell.color('2023-08-06T03:08:27+00:00', :red)} - #{Shell.color('older than 12 days', :red)})
        - my-app-test-5:513_ec7930a (#{Shell.color('2023-08-07T13:20:18+00:00', :red)} - #{Shell.color('older than 12 days', :red)})
    OUTPUT

    output = command_output do
      args = ["-a", "my-app-test-5"]
      Cpl::Cli.start([described_class::NAME, *args])
    end

    expect(Shell).to have_received(:confirm).once
    expect(output).to eq(expected_output)
  end

  it "deletes images", vcr: true do
    allow(Shell).to receive(:confirm).with("\nAre you sure you want to delete these 6 images?")
                                     .and_return(true)

    expected_output = <<~OUTPUT
      Images to delete:
        - my-app-test-3:508_149ba15 (#{Shell.color('2023-08-02T08:35:20+00:00', :red)} - #{Shell.color('exceeds max quantity of 15', :red)})
        - my-app-test-3:509_1ddaddb (#{Shell.color('2023-08-03T08:50:12+00:00', :red)} - #{Shell.color('exceeds max quantity of 15', :red)})
        - my-app-test-3:510_ad671e6 (#{Shell.color('2023-08-04T01:17:29+00:00', :red)} - #{Shell.color('exceeds max quantity of 15', :red)})
        - my-app-test-3:511_7ef99dd (#{Shell.color('2023-08-05T02:51:14+00:00', :red)} - #{Shell.color('older than 15 days', :red)})
        - my-app-test-3:512_346384f (#{Shell.color('2023-08-06T03:08:27+00:00', :red)} - #{Shell.color('older than 15 days', :red)})
        - my-app-test-3:513_ec7930a (#{Shell.color('2023-08-07T13:20:18+00:00', :red)} - #{Shell.color('older than 15 days', :red)})

      Deleting image 'my-app-test-3:508_149ba15'... #{Shell.color('done!', :green)}
      Deleting image 'my-app-test-3:509_1ddaddb'... #{Shell.color('done!', :green)}
      Deleting image 'my-app-test-3:510_ad671e6'... #{Shell.color('done!', :green)}
      Deleting image 'my-app-test-3:511_7ef99dd'... #{Shell.color('done!', :green)}
      Deleting image 'my-app-test-3:512_346384f'... #{Shell.color('done!', :green)}
      Deleting image 'my-app-test-3:513_ec7930a'... #{Shell.color('done!', :green)}
    OUTPUT

    output = command_output do
      args = ["-a", "my-app-test-3"]
      Cpl::Cli.start([described_class::NAME, *args])
    end

    expect(Shell).to have_received(:confirm).once
    expect(output).to eq(expected_output)
  end

  it "skips delete confirmation", vcr: true do
    allow(Shell).to receive(:confirm)

    expected_output = <<~OUTPUT
      Images to delete:
        - my-app-test-3:508_149ba15 (#{Shell.color('2023-08-02T08:35:20+00:00', :red)} - #{Shell.color('exceeds max quantity of 15', :red)})
        - my-app-test-3:509_1ddaddb (#{Shell.color('2023-08-03T08:50:12+00:00', :red)} - #{Shell.color('exceeds max quantity of 15', :red)})
        - my-app-test-3:510_ad671e6 (#{Shell.color('2023-08-04T01:17:29+00:00', :red)} - #{Shell.color('exceeds max quantity of 15', :red)})
        - my-app-test-3:511_7ef99dd (#{Shell.color('2023-08-05T02:51:14+00:00', :red)} - #{Shell.color('older than 15 days', :red)})
        - my-app-test-3:512_346384f (#{Shell.color('2023-08-06T03:08:27+00:00', :red)} - #{Shell.color('older than 15 days', :red)})
        - my-app-test-3:513_ec7930a (#{Shell.color('2023-08-07T13:20:18+00:00', :red)} - #{Shell.color('older than 15 days', :red)})

      Deleting image 'my-app-test-3:508_149ba15'... #{Shell.color('done!', :green)}
      Deleting image 'my-app-test-3:509_1ddaddb'... #{Shell.color('done!', :green)}
      Deleting image 'my-app-test-3:510_ad671e6'... #{Shell.color('done!', :green)}
      Deleting image 'my-app-test-3:511_7ef99dd'... #{Shell.color('done!', :green)}
      Deleting image 'my-app-test-3:512_346384f'... #{Shell.color('done!', :green)}
      Deleting image 'my-app-test-3:513_ec7930a'... #{Shell.color('done!', :green)}
    OUTPUT

    output = command_output do
      args = ["-a", "my-app-test-3", "-y"]
      Cpl::Cli.start([described_class::NAME, *args])
    end

    expect(Shell).not_to have_received(:confirm)
    expect(output).to eq(expected_output)
  end
end
