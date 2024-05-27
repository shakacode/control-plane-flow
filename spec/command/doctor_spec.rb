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

      result = run_cpl_command("doctor", "--validations", "config")

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("[FAIL] config")
      expect(result[:stderr]).to include("- '#{app_prefix}' is a prefix of '#{app_prefix}-full'")
      expect(result[:stderr]).to include("- '#{app_prefix}' is a prefix of '#{app_prefix}-1'")
      expect(result[:stderr]).to include("- '#{app_prefix}' is a prefix of '#{app_prefix}-2'")
    end

    it "passes if there are no issues" do
      temporarily_switch_config_file("valid-app-names")

      result = run_cpl_command("doctor", "--validations", "config")

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("[PASS] config")
    end
  end

  context "when validating templates" do
    let!(:app) { dummy_test_app }

    it "raises error if app is not provided" do
      result = run_cpl_command("doctor", "--validations", "templates")

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("App is required for templates validation")
    end

    it "fails if there are duplicate templates" do
      stub_template_filenames("app", "app-without-identity", "rails")

      result = run_cpl_command("doctor", "--validations", "templates", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("[FAIL] templates")
      expect(result[:stderr]).to include("- kind: gvc, name: #{app}")
    end

    it "passes if there are no issues" do
      stub_template_filenames("app", "rails")

      result = run_cpl_command("doctor", "--validations", "templates", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("[PASS] templates")
      expect(result[:stderr]).not_to include("DEPRECATED")
    end

    it "warns about deprecated variables" do
      stub_template_filenames("app-with-deprecated-variables")

      result = run_cpl_command("doctor", "--validations", "templates", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("[PASS] templates")
      expect(result[:stderr]).to include("DEPRECATED")
      expect(result[:stderr]).to include("APP_ORG -> {{APP_ORG}}")
      expect(result[:stderr]).to include("APP_GVC -> {{APP_NAME}}")
      expect(result[:stderr]).to include("APP_LOCATION -> {{APP_LOCATION}}")
      expect(result[:stderr]).to include("APP_IMAGE -> {{APP_IMAGE}}")
    end
  end

  context "when validation is not recognized" do
    it "raises error" do
      result = run_cpl_command("doctor", "--validations", "unknown")

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
