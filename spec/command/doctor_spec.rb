# frozen_string_literal: true

require "spec_helper"

describe Command::Doctor do
  context "when validating config" do
    let!(:app_prefix) { dummy_test_app_prefix }

    after do
      restore_config_file
    end

    it "fails if there are app names contained in others" do
      temporarily_switch_config_file("invalid-app-names")

      result = run_cpflow_command("doctor", "--validations", "config")

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("[FAIL] config")
      expect(result[:stderr]).to include("- '#{app_prefix}' is a prefix of '#{app_prefix}-full'")
      expect(result[:stderr]).to include("- '#{app_prefix}' is a prefix of '#{app_prefix}-1'")
      expect(result[:stderr]).to include("- '#{app_prefix}' is a prefix of '#{app_prefix}-2'")
    end

    it "passes if there are no issues" do
      temporarily_switch_config_file("valid-app-names")

      result = run_cpflow_command("doctor", "--validations", "config")

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("[PASS] config")
    end
  end

  context "when validating templates" do
    let!(:app) { dummy_test_app("default") }

    it "raises error if app is not provided" do
      result = run_cpflow_command("doctor", "--validations", "templates")

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("App is required for templates validation")
    end

    it "fails if selected templates contain duplicate rendered kind/names" do
      app = dummy_test_app("duplicate-templates")

      result = run_cpflow_command("doctor", "--validations", "templates", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("[FAIL] templates")
      expect(result[:stderr]).to include("- kind: gvc, name: #{app}")
    end

    it "fails cleanly if the current app config is missing" do
      progress = StringIO.new
      config = instance_double(Config, args: [], current: nil)
      command = instance_double(described_class, config: config, progress: progress)

      expect { DoctorService.new(command).run_validations(["templates"]) }.to raise_error(SystemExit)
      expect(progress.string).to include("[FAIL] templates")
      expect(progress.string).to include("Can't find current config, please specify an app.")
      expect(progress.string).not_to include("NoMethodError")
    end

    it "fails if a selected setup template is missing" do
      app = dummy_test_app("missing-template")

      result = run_cpflow_command("doctor", "--validations", "templates", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("[FAIL] templates")
      expect(result[:stderr]).to include("Missing templates")
      expect(result[:stderr]).to include("- nonexistent")
    end

    it "fails if an explicitly named template is missing" do
      Dir.mktmpdir do |dir|
        progress = StringIO.new
        config = instance_double(Config, args: ["nonexistent"], app_cpln_dir: dir)
        command = instance_double(described_class, config: config, progress: progress)

        expect { DoctorService.new(command).run_validations(["templates"]) }.to raise_error(SystemExit)
        expect(progress.string).to include("[FAIL] templates")
        expect(progress.string).to include("Missing templates")
        expect(progress.string).to include("- nonexistent")
      end
    end

    it "validates all templates if no setup templates are selected" do
      app = dummy_test_app("nothing")
      stub_template_filenames("app", "app-without-identity")

      result = run_cpflow_command("doctor", "--validations", "templates", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("[FAIL] templates")
      expect(result[:stderr]).to include("- kind: gvc, name: #{app}")
    end

    it "passes if unselected templates render duplicate kind/names" do
      app = dummy_test_app("alternate-app-template")

      result = run_cpflow_command("doctor", "--validations", "templates", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("[PASS] templates")
      expect(result[:stderr]).not_to include("DEPRECATED")
    end

    it "passes if selected templates have no issues" do
      result = run_cpflow_command("doctor", "--validations", "templates", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("[PASS] templates")
      expect(result[:stderr]).not_to include("DEPRECATED")
    end

    it "warns about deprecated variables" do
      app = dummy_test_app("deprecated-template")

      result = run_cpflow_command("doctor", "--validations", "templates", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("[PASS] templates")
      expect(result[:stderr]).to include("DEPRECATED")
      expect(result[:stderr]).to include("APP_ORG -> {{APP_ORG}}")
      expect(result[:stderr]).to include("APP_GVC -> {{APP_NAME}}")
      expect(result[:stderr]).to include("APP_LOCATION -> {{APP_LOCATION}}")
      expect(result[:stderr]).not_to include("APP_IMAGE -> {{APP_IMAGE}}")
    end

    it "warns about a deprecated bare APP_IMAGE variable" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p("#{dir}/templates")
        File.write("#{dir}/templates/legacy.yml", <<~YAML)
          kind: identity
          name: APP_IMAGE
        YAML

        progress = StringIO.new
        config = instance_double(
          Config,
          args: [],
          current: { setup_app_templates: ["legacy"] },
          app_cpln_dir: dir,
          org: "test-org",
          app: "test-app",
          location: "aws-us-east-2",
          location_link: "/org/test-org/location/aws-us-east-2",
          identity: "test-app-identity",
          identity_link: "/org/test-org/gvc/test-app/identity/test-app-identity",
          secrets: "test-app-secrets",
          secrets_policy: "test-app-secrets-policy",
          shared_secret_placeholders: {}
        )
        cp = instance_double(Controlplane, latest_image: "test-app:1")
        command = instance_double(described_class, config: config, progress: progress, cp: cp)

        DoctorService.new(command).run_validations(["templates"])

        expect(progress.string).to include("[PASS] templates")
        expect(progress.string).to include("APP_IMAGE -> {{APP_IMAGE}}")
      end
    end
  end

  context "when validation is not recognized" do
    it "raises error" do
      result = run_cpflow_command("doctor", "--validations", "unknown")

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Invalid value provided for option --validations")
    end
  end

  def stub_template_filenames(*names)
    allow(Dir).to receive(:glob).and_wrap_original do |method, *args|
      method.call(*args).select do |filename|
        names.any? { |name| filename.end_with?("#{name}.yml") }
      end
    end
  end
end
