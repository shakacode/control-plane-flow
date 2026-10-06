# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Command::BuildImage do
  let(:directory) { Dir.mktmpdir("cpflow secret mount ") }
  let(:context) { File.join(directory, "context") }
  let(:image_name) { "build-secret-test:#{Process.pid}" }
  let(:config) do
    instance_double(Config, app: "test-app", org: nil, current: {}, app_cpln_dir: context, app_dir: context)
  end
  let(:cp) { Controlplane.new(config) }

  before do
    FileUtils.mkdir_p(context)
    File.write(secret_path, "dummy token=123")
    File.write(File.join(context, "Dockerfile"), <<~DOCKERFILE)
      FROM busybox:1.37.0
      RUN --mount=type=secret,id=build_token,required=true test "$(cat /run/secrets/build_token)" = "dummy token=123"
      RUN test ! -e /run/secrets/build_token
    DOCKERFILE
    # Keep CLI parsing, the command, and Docker execution real; replace registry operations only.
    allow(cp).to receive_messages(
      latest_image_next: image_name,
      image_push: true,
      query_images: { "items" => [{ "name" => image_name }] }
    )
    allow(config).to receive(:org).and_return("test-org")
    allow(Controlplane).to receive(:new).with(config).and_return(cp)
    allow(Config).to receive(:new) do |args, options, _required_options|
      allow(config).to receive_messages(args: args, options: options)
      config
    end
    allow(Cpflow::Cli).to receive(:show_info_header)
  end

  after do
    FileUtils.remove_entry(directory)
  end

  def secret_path
    File.join(directory, "build token")
  end

  def image_url
    "test-org.registry.cpln.io/#{image_name}"
  end

  def build_with_secret
    run_cpflow_command("build-image", "-a", "test-app", "--secret=id=build_token,src=#{secret_path}", "--no-cache")
  end

  it "forwards a secret with a spaced path through the CLI to Docker's argv" do
    allow(Shell).to receive(:cmd).with("docker", "version", capture_stderr: true).and_return(success: true)
    allow(cp).to receive(:kernel_system_with_pid_handling).and_return(true)

    result = build_with_secret

    expect(result[:status]).to eq(0), result[:stderr]
    expect(cp).to have_received(:kernel_system_with_pid_handling).with(
      ["docker", "build", "--platform=linux/amd64", "-t", image_url, "-f", File.join(context, "Dockerfile"),
       "--secret=id=build_token,src=#{secret_path}", "--no-cache", context],
      anything
    )
  end

  it "lets a Dockerfile consume the secret without persisting the mount", :docker_integration, :slow do
    allow(cp).to receive(:determine_command_output_mode).and_return(:all)
    result = build_with_secret

    expect(result[:status]).to eq(0), result[:stderr]
  ensure
    Shell.cmd("docker", "image", "rm", "--force", image_url, capture_stderr: true)
  end
end
