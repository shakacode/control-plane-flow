# frozen_string_literal: true

require "spec_helper"

describe Controlplane do
  describe "#initialize" do
    let!(:fake_config) { Struct.new(:app, :org).new("my-app", "my-org") }

    it "raises error if org does not exist" do
      allow_any_instance_of(ControlplaneApi).to receive(:list_orgs).and_return({ "items" => [] }) # rubocop:disable RSpec/AnyInstance

      expect do
        described_class.new(fake_config)
      end.to raise_error(include("Can't find org 'my-org'"))
    end

    it "allows scoped tokens that cannot list orgs to continue to the target API call" do
      allow_any_instance_of(ControlplaneApi).to receive(:list_orgs).and_return(nil) # rubocop:disable RSpec/AnyInstance

      expect { described_class.new(fake_config) }.not_to raise_error
    end

    it "allows scoped tokens that are forbidden from listing orgs to continue to the target API call" do
      response = instance_double(Net::HTTPForbidden, body: '{"message":"forbidden"}', to_s: "403 Forbidden")
      error = ControlplaneApiDirect::ForbiddenError.new(url: "/org", response: response)
      allow_any_instance_of(ControlplaneApi).to receive(:list_orgs).and_raise(error) # rubocop:disable RSpec/AnyInstance

      expect { described_class.new(fake_config) }.not_to raise_error
    end
  end

  describe "argv-safe profile, image, and GVC commands" do
    let(:config) do
      instance_double(
        Config,
        app: "my app; printf pwned",
        org: "my org $(id)",
        should_app_start_with?: false
      )
    end
    let(:described_instance) do
      described_class.allocate.tap do |instance|
        instance.instance_variable_set(:@config, config)
        instance.instance_variable_set(:@gvc, config.app)
        instance.instance_variable_set(:@org, config.org)
      end
    end

    before do
      allow(described_instance).to receive_messages(perform!: true, perform_yaml!: [{}])
    end

    it "keeps every dynamic token as one argv element" do
      described_instance.profile_exists?("profile; touch marker")
      described_instance.profile_create("profile name", "token $(id)")
      described_instance.profile_delete("profile`id`")
      described_instance.image_build(
        "registry/image;id",
        dockerfile: "Docker file",
        docker_context: "context;id",
        docker_args: ["--label=payload=$(id)"],
        build_args: ["COMMIT=value with spaces"]
      )
      described_instance.image_login
      described_instance.image_pull("registry/image;id")
      described_instance.image_tag("old image", "new;image")
      described_instance.image_push("registry/image$(id)")
      described_instance.gvc_query

      expect(described_instance).to have_received(:perform_yaml!).with(
        ["cpln", "profile", "get", "profile; touch marker", "-o", "yaml"]
      )
      expect(described_instance).to have_received(:perform!).with(
        ["cpln", "profile", "create", "profile name", "--token", "token $(id)"],
        sensitive_data_pattern: /(?<=--token ).+\z/m
      )
      expect(described_instance).to have_received(:perform!).with(
        ["cpln", "profile", "delete", "profile`id`"]
      )
      expect(described_instance).to have_received(:perform!).with(
        [
          "docker", "build", "--platform=linux/amd64",
          "-t", "registry/image;id", "-f", "Docker file",
          "--label=payload=$(id)", "--build-arg", "COMMIT=value with spaces",
          "context;id"
        ]
      )
      expect(described_instance).to have_received(:perform!).with(
        ["cpln", "image", "docker-login", "--org", "my org $(id)"], output_mode: :none
      )
      expect(described_instance).to have_received(:perform!).with(
        ["docker", "pull", "registry/image;id"], output_mode: :none
      )
      expect(described_instance).to have_received(:perform!).with(["docker", "tag", "old image", "new;image"])
      expect(described_instance).to have_received(:perform!).with(["docker", "push", "registry/image$(id)"])
      expect(described_instance).to have_received(:perform_yaml!).with(
        [
          "cpln", "gvc", "query", "--org", "my org $(id)",
          "-o", "yaml", "--prop", "name=my app; printf pwned"
        ]
      )
    end
  end

  describe "profile token redaction" do
    let(:described_instance) { described_class.allocate }
    let(:process_status) { instance_double(Process::Status, exited?: true, success?: true) }

    it "redacts the complete escaped token while still passing it as one argv element" do
      warnings = []
      allow(Kernel).to receive(:warn) { |message| warnings << message }
      allow(Process).to receive(:spawn).and_return(1234)
      allow(Process).to receive(:wait2).with(1234).and_return([1234, process_status])
      stub_env("HIDE_COMMAND_OUTPUT", nil)
      Shell.verbose_mode(true)

      token = "secret value;\n$(id)"
      described_instance.profile_create("profile name", token)

      expect(Process).to have_received(:spawn).with(
        "cpln", "profile", "create", "profile name", "--token", token
      )
      expect(warnings.join).to include("--token XXXXXXX")
      expect(warnings.join).not_to include("secret", "value", "$(id)")
    ensure
      Shell.verbose_mode(false)
    end
  end

  describe "#workload_exec" do
    let(:described_instance) do
      described_class.allocate.tap do |instance|
        instance.instance_variable_set(:@gvc, "my app")
        instance.instance_variable_set(:@org, "my org")
      end
    end
    let(:process_status) { instance_double(Process::Status, exited?: true, success?: true) }

    before do
      allow(Process).to receive(:spawn).and_return(1234)
      allow(Process).to receive(:wait2).with(1234).and_return([1234, process_status])
    end

    it "spawns local cpln command arguments without shell interpolation" do
      command = ["bash", "-c", 'eval "$CPFLOW_RUNNER_SCRIPT"']

      result = described_instance.workload_exec(
        "rails runner", "replica;id", location: "location $HOME", container: "rails`id`", command: command
      )

      expect(result).to be(true)
      expect(Process).to have_received(:spawn).with(
        "cpln", "workload", "exec", "rails runner",
        "--gvc", "my app", "--org", "my org",
        "--replica", "replica;id", "--location", "location $HOME", "-it",
        "--container", "rails`id`", "--",
        "bash", "-c", 'eval "$CPFLOW_RUNNER_SCRIPT"'
      )
    end
  end

  describe "#kernel_system_with_pid_handling" do
    let(:described_instance) { described_class.allocate }
    let(:process_status) { instance_double(Process::Status, exited?: true, success?: true) }

    before do
      allow(Process).to receive(:spawn).and_return(1234)
      allow(Process).to receive(:wait2).with(1234).and_return([1234, process_status])
    end

    it "passes capture options to an argv-safe process spawn" do
      output = instance_double(IO)

      result = described_instance.send(
        :kernel_system_with_pid_handling,
        ["cpln", "workload", "update", "rails runner"],
        out: output,
        err: %i[child out]
      )

      expect(result).to be(true)
      expect(Process).to have_received(:spawn).with(
        "cpln", "workload", "update", "rails runner",
        out: output,
        err: %i[child out]
      )
    end

    it "rejects single-string commands before they can invoke a shell" do
      expect do
        described_instance.send(:kernel_system_with_pid_handling, "cpln workload update rails")
      end.to raise_error(ArgumentError, "Commands must be argv arrays with at least two elements.")

      expect(Process).not_to have_received(:spawn)
    end

    it "rejects one-element arrays because splatting them can still invoke a shell" do
      expect do
        described_instance.send(:kernel_system_with_pid_handling, ["cpln workload update rails; touch marker"])
      end.to raise_error(ArgumentError, "Commands must be argv arrays with at least two elements.")

      expect(Process).not_to have_received(:spawn)
    end
  end

  describe "#perform_yaml" do
    let(:described_instance) { described_class.allocate }

    it "rejects single-string commands before they can reach Open3" do
      allow(Shell).to receive(:cmd)

      expect do
        described_instance.send(:perform_yaml, "cpln workload get rails -o yaml")
      end.to raise_error(ArgumentError, "Commands must be argv arrays with at least two elements.")

      expect(Shell).not_to have_received(:cmd)
    end
  end

  describe "#command_spawn_options" do
    let!(:fake_config) { Struct.new(:app, :org).new("my-app", nil) }
    let!(:described_instance) { described_class.new(fake_config) }

    before do
      stub_env("HIDE_COMMAND_OUTPUT", nil)
      allow(Shell).to receive(:should_hide_output?).and_return(false)
    end

    it "does not hide anything by default" do
      spawn_options = described_instance.send(:command_spawn_options)

      expect(spawn_options).to eq({})
    end

    it "does not hide anything when 'output_mode' is :all" do
      spawn_options = described_instance.send(:command_spawn_options, :all)

      expect(spawn_options).to eq({})
    end

    it "hides stdout when 'output_mode' is :errors_only" do
      spawn_options = described_instance.send(:command_spawn_options, :errors_only)

      expect(spawn_options).to eq(out: File::NULL)
    end

    it "hides everything when 'output_mode' is :none" do
      spawn_options = described_instance.send(:command_spawn_options, :none)

      expect(spawn_options).to eq(out: File::NULL, err: File::NULL)
    end

    it "hides everything when 'HIDE_COMMAND_OUTPUT' env var is set to 'true'" do
      stub_env("HIDE_COMMAND_OUTPUT", "true")

      spawn_options = described_instance.send(:command_spawn_options)

      expect(spawn_options).to eq(out: File::NULL, err: File::NULL)
    end

    it "provided 'output_mode' overrides 'HIDE_COMMAND_OUTPUT' env var" do
      stub_env("HIDE_COMMAND_OUTPUT", "true")

      spawn_options = described_instance.send(:command_spawn_options, :all)

      expect(spawn_options).to eq({})
    end

    it "hides stdout when 'Shell.should_hide_output?' is true" do
      allow(Shell).to receive(:should_hide_output?).and_return(true)

      spawn_options = described_instance.send(:command_spawn_options)

      expect(spawn_options).to eq(out: File::NULL)
    end

    it "raises error when 'output_mode' is invalid" do
      expect do
        described_instance.send(:command_spawn_options, :invalid)
      end.to raise_error("Invalid command output mode 'invalid'.")
    end
  end

  describe "#perform" do
    let(:described_instance) { described_class.allocate }
    let(:process_status) { instance_double(Process::Status, exited?: true, success?: true) }

    before do
      allow(Process).to receive(:spawn).and_return(1234)
      allow(Process).to receive(:wait2).with(1234).and_return([1234, process_status])
    end

    it "suppresses only stdout without converting argv back into a shell command" do
      result = described_instance.send(:perform, %w[cpln image docker-login], output_mode: :errors_only)

      expect(result).to be(true)
      expect(Process).to have_received(:spawn).with(
        "cpln", "image", "docker-login",
        out: File::NULL
      )
    end
  end

  describe "#fetch_workload_with_status" do
    let(:described_instance) do
      described_class.allocate.tap do |instance|
        instance.instance_variable_set(:@gvc, "my-app")
        instance.instance_variable_set(:@org, "my-org")
      end
    end

    it "returns the workload with computed status from the CLI" do
      workload = { "name" => "rails", "status" => { "readyLatest" => true } }
      allow(Shell).to receive(:cmd).with(
        "cpln", "workload", "get", "rails",
        "--gvc", "my-app", "--org", "my-org", "-o", "json",
        separate_stderr: true
      ).and_return({ success: true, output: JSON.generate(workload), error_output: "update available" })

      expect(described_instance.fetch_workload_with_status("rails")).to eq(workload)
    end

    it "warns and returns nil when the CLI lookup fails" do
      allow(Shell).to receive(:cmd).and_return({ success: false, output: "", error_output: "not authorized" })
      allow(Shell).to receive(:warn)

      expect(described_instance.fetch_workload_with_status("rails")).to be_nil
      expect(Shell).to have_received(:warn).with(
        "Failed to fetch status for 'rails': not authorized"
      )
    end

    it "warns and returns nil when the CLI output is not JSON" do
      allow(Shell).to receive(:cmd).and_return({ success: true, output: "not json", error_output: "" })
      allow(Shell).to receive(:warn)

      expect(described_instance.fetch_workload_with_status("rails")).to be_nil
      expect(Shell).to have_received(:warn).with(
        a_string_starting_with("Failed to parse status for 'rails':")
      )
    end
  end

  describe "argv-safe workload and log commands" do
    let(:config) { instance_double(Config, org: "my org; id") }
    let(:described_instance) do
      described_class.allocate.tap do |instance|
        instance.instance_variable_set(:@config, config)
        instance.instance_variable_set(:@gvc, "my app $(id)")
        instance.instance_variable_set(:@org, "my org; id")
      end
    end

    before do
      allow(described_instance).to receive_messages(
        perform: true,
        perform!: true,
        perform_yaml: { "items" => [] }
      )
    end

    it "keeps resource, container, replica, and location values literal" do
      described_instance.fetch_workload_replicas("rails; touch marker", location: "location $(id)")
      described_instance.stop_workload_replica(
        "rails; id", "replica $(id)", location: "location`id`"
      )
      described_instance.workload_force_redeployment("rails; id")
      described_instance.workload_connect(
        "rails; id", location: "location $(id)", container: "web`id`", shell: "/bin/sh; id"
      )
      described_instance.start_cron_workload("worker; id", "kind: cron", location: "location $(id)")
      described_instance.fetch_cron_workload("worker`id`", location: "location; id")
      described_instance.logs(
        workload: "rails; id", replica: "replica $(id)", limit: "10; id", since: "5m $(id)"
      )

      expect(described_instance).to have_received(:perform_yaml).with(
        [
          "cpln", "workload", "replica", "get", "rails; touch marker",
          "--gvc", "my app $(id)", "--org", "my org; id",
          "--location", "location $(id)", "-o", "yaml"
        ],
        err: File::NULL
      )
      expect(described_instance).to have_received(:perform).with(
        [
          "cpln", "workload", "replica", "stop", "rails; id",
          "--gvc", "my app $(id)", "--org", "my org; id",
          "--replica-name", "replica $(id)", "--location", "location`id`"
        ],
        output_mode: :none
      )
      expect(described_instance).to have_received(:perform!).with(
        [
          "cpln", "workload", "force-redeployment", "rails; id",
          "--gvc", "my app $(id)", "--org", "my org; id"
        ]
      )
      expect(described_instance).to have_received(:perform!).with(
        [
          "cpln", "workload", "connect", "rails; id",
          "--gvc", "my app $(id)", "--org", "my org; id",
          "--location", "location $(id)",
          "--container", "web`id`", "--shell", "/bin/sh; id"
        ],
        output_mode: :all
      )
      expect(described_instance).to have_received(:perform_yaml).with(
        [
          "cpln", "workload", "cron", "start", "worker; id",
          "--gvc", "my app $(id)", "--org", "my org; id",
          "--file", an_instance_of(String), "--location", "location $(id)", "-o", "yaml"
        ]
      )
      expect(described_instance).to have_received(:perform_yaml).with(
        [
          "cpln", "workload", "cron", "get", "worker`id`",
          "--gvc", "my app $(id)", "--org", "my org; id",
          "--location", "location; id", "-o", "yaml"
        ]
      )
      expect(described_instance).to have_received(:perform!).with(
        [
          "cpln", "logs",
          '{gvc="my app $(id)",workload="rails; id",replica="replica $(id)"}',
          "--org", "my org; id", "-t", "-o", "raw",
          "--limit", "10; id", "--since", "5m $(id)"
        ],
        output_mode: :all
      )
    end
  end

  describe "argv-safe policy commands" do
    let(:described_instance) do
      described_class.allocate.tap do |instance|
        instance.instance_variable_set(:@org, "my org; id")
      end
    end

    before do
      allow(described_instance).to receive(:perform!).and_return(true)
    end

    it "keeps policy, identity, and permission values literal" do
      described_instance.bind_identity_to_policy("identity; id", "policy $(id)")
      described_instance.unbind_identity_from_policy(
        "identity`id`", "policy; id", permission: "edit $(id)"
      )

      expect(described_instance).to have_received(:perform!).with(
        [
          "cpln", "policy", "add-binding", "policy $(id)",
          "--org", "my org; id", "--identity", "identity; id",
          "--permission", "reveal"
        ]
      )
      expect(described_instance).to have_received(:perform!).with(
        [
          "cpln", "policy", "remove-binding", "policy; id",
          "--org", "my org; id", "--identity", "identity`id`",
          "--permission", "edit $(id)"
        ]
      )
    end
  end

  describe "#apply_template argv handling" do
    let(:described_instance) do
      described_class.allocate.tap do |instance|
        instance.instance_variable_set(:@gvc, "my app; id")
        instance.instance_variable_set(:@org, "my org $(id)")
      end
    end

    it "passes the generated template path and resource names as argv" do
      allow(Shell).to receive(:cmd).and_return(
        output: "Updated workload 'rails'\n",
        success: true
      )

      result = described_instance.apply_template("kind: workload")

      expect(result).to eq([{ kind: "workload", name: "rails" }])
      expect(Shell).to have_received(:cmd).with(
        "cpln", "apply",
        "--gvc", "my app; id", "--org", "my org $(id)",
        "--file", an_instance_of(String)
      )
    end

    it "captures hidden stderr with a spawn option and preserves non-aborting failures" do
      allow(Shell).to receive_messages(
        should_hide_output?: true,
        cmd: { output: "", success: false }
      )
      allow(Shell).to receive(:abort)

      Shell.use_tmp_stderr do
        tmp_stderr = Shell.tmp_stderr

        expect(described_instance.apply_template("kind: workload")).to be_nil
        expect(Shell).to have_received(:cmd).with(
          "cpln", "apply",
          "--gvc", "my app; id", "--org", "my org $(id)",
          "--file", an_instance_of(String),
          err: tmp_stderr
        )
      end

      expect(Shell).not_to have_received(:abort)
    end
  end

  describe "#set_workload_suspend" do
    let(:api) { instance_double(ControlplaneApi) }
    let(:described_instance) do
      described_class.allocate.tap do |instance|
        instance.instance_variable_set(:@gvc, "prefix")
        instance.instance_variable_set(:@org, "my-org")
        instance.instance_variable_set(:@api, api)
      end
    end
    let(:workload_data) do
      { "spec" => { "defaultOptions" => { "suspend" => false } } }
    end

    it "targets an explicitly selected GVC for stale-app cleanup" do
      allow(api).to receive(:workload_get)
        .with(org: "my-org", gvc: "matched-stale-app", workload: "postgres")
        .and_return(workload_data)
      allow(api).to receive(:update_workload)

      expect(described_instance.set_workload_suspend("postgres", true, "matched-stale-app")).to be_nil

      expect(api).to have_received(:update_workload).with(
        org: "my-org",
        gvc: "matched-stale-app",
        workload: "postgres",
        data: { "spec" => { "defaultOptions" => { "suspend" => true } } }
      )
    end

    it "treats a missing workload as already suspended when requested" do
      allow(api).to receive(:workload_get)
        .with(org: "my-org", gvc: "matched-stale-app", workload: "postgres")
        .and_return(nil)
      allow(api).to receive(:update_workload)

      expect(
        described_instance.set_workload_suspend("postgres", true, "matched-stale-app", missing_ok: true)
      ).to be(true)
      expect(api).not_to have_received(:update_workload)
    end

    it "still raises for a missing workload by default" do
      allow(api).to receive(:workload_get)
        .with(org: "my-org", gvc: "matched-stale-app", workload: "postgres")
        .and_return(nil)

      expect do
        described_instance.set_workload_suspend("postgres", true, "matched-stale-app")
      end.to raise_error("Can't find workload 'postgres', " \
                         "please create it with 'cpflow apply-template postgres -a matched-stale-app'.")
    end

    it "treats a workload deleted during the suspend update as already suspended when requested" do
      allow(api).to receive(:workload_get)
        .with(org: "my-org", gvc: "matched-stale-app", workload: "postgres")
        .and_return(workload_data)
      allow(api).to receive(:update_workload).and_return(nil)

      expect(
        described_instance.set_workload_suspend("postgres", true, "matched-stale-app", missing_ok: true)
      ).to be(true)
    end
  end

  describe "#image_build" do
    let!(:fake_config) { Struct.new(:app, :org).new("my-app", nil) }
    let!(:described_instance) { described_class.new(fake_config) }

    it "passes Docker build tokens as exact argv" do
      allow(described_instance).to receive(:perform!)

      described_instance.image_build(
        "example.registry.cpln.io/my-app:1",
        dockerfile: ".controlplane/Dockerfile",
        docker_context: ".",
        docker_args: ["--build-arg=PAYLOAD=$(touch${IFS}/tmp/pwned)"],
        build_args: ["GIT_COMMIT=abc123"]
      )

      expect(described_instance).to have_received(:perform!) do |cmd|
        expect(cmd).to eq(
          [
            "docker", "build", "--platform=linux/amd64",
            "-t", "example.registry.cpln.io/my-app:1",
            "-f", ".controlplane/Dockerfile",
            "--build-arg=PAYLOAD=$(touch${IFS}/tmp/pwned)",
            "--build-arg", "GIT_COMMIT=abc123",
            "."
          ]
        )
      end
    end
  end

  describe "#workload_set_image_ref" do
    let(:fake_config) { Struct.new(:app, :org).new("my-app", "my-org") }
    let(:described_instance) { described_class.new(fake_config) }

    before do
      allow_any_instance_of(ControlplaneApi).to receive(:list_orgs).and_return({ "items" => [{ "name" => "my-org" }] }) # rubocop:disable RSpec/AnyInstance
      allow(described_instance).to receive(:perform_with_output).and_call_original
      allow(described_instance).to receive(:perform_with_output)
        .with(
          [
            "cpln", "workload", "update", "rails",
            "--gvc", "my-app", "--org", "my-org",
            "--set", "spec.containers.web.image=/org/my-org/image/my-app:2"
          ]
        )
        .and_return({ success: false, output: "409 Conflict" })
    end

    it "returns the captured command result so the caller can classify the failure" do
      result = described_instance.workload_set_image_ref(
        "rails",
        container: "web",
        image: "my-app:2"
      )

      expect(result).to eq(success: false, output: "409 Conflict")
    end

    it "tracks the captured subprocess until it exits" do
      process_status = instance_double(Process::Status, exited?: true, success?: false)
      allow(Process).to receive(:spawn).and_return(12_345)
      allow(Process).to receive(:wait2).with(12_345) do
        expect($child_pids).to include(12_345) # rubocop:disable Style/GlobalVars
        [12_345, process_status]
      end

      result = described_instance.send(:perform_with_output, %w[cpln workload update])

      expect(result).to eq(success: false, output: "")
      expect(Process).to have_received(:spawn).with(
        "cpln", "workload", "update",
        out: an_instance_of(File),
        err: %i[child out]
      )
      expect($child_pids).not_to include(12_345) # rubocop:disable Style/GlobalVars
    end

    it "passes image metacharacters as one literal argument without executing a second command" do
      Dir.mktmpdir("cpflow-argv") do |dir|
        fake_cpln = File.join(dir, "cpln")
        argv_log = File.join(dir, "argv.json")
        marker = File.join(dir, "shell-command-ran")
        previous_path = ENV.fetch("PATH")
        previous_argv_log = ENV.fetch("CPFLOW_ARGV_LOG", nil)

        File.write(fake_cpln, <<~RUBY)
          #!/usr/bin/env ruby
          require "json"
          File.write(ENV.fetch("CPFLOW_ARGV_LOG"), JSON.generate(ARGV))
          puts "updated"
        RUBY
        File.chmod(0o755, fake_cpln)
        ENV["PATH"] = "#{dir}:#{previous_path}"
        ENV["CPFLOW_ARGV_LOG"] = argv_log

        image = "my-app:2; touch #{marker}"
        result = described_instance.workload_set_image_ref("rails", container: "web", image: image)

        expect(result).to eq(success: true, output: "updated\n")
        expect(File).not_to exist(marker)
        expect(JSON.parse(File.read(argv_log))).to eq(
          [
            "workload", "update", "rails",
            "--gvc", "my-app", "--org", "my-org",
            "--set", "spec.containers.web.image=/org/my-org/image/#{image}"
          ]
        )
      ensure
        ENV["PATH"] = previous_path
        ENV["CPFLOW_ARGV_LOG"] = previous_argv_log
      end
    end
  end
end
