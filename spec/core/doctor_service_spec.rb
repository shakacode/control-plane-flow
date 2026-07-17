# frozen_string_literal: true

require "spec_helper"
require "pathname"
require "stringio"
require "tmpdir"

describe DoctorService do
  let(:progress) { StringIO.new }
  let(:command) { instance_double(Command::Doctor, config: config, progress: progress) }

  def service
    described_class.new(command)
  end

  def expect_validations_to_fail(validations)
    expect { service.run_validations(validations) }.to raise_error(
      an_instance_of(SystemExit).and(having_attributes(status: ExitCode::ERROR_DEFAULT))
    )
  end

  describe "#run_validations" do
    context "with an unknown validation" do
      let(:config) { instance_double(Config) }

      it "fails the run and exits" do
        expect_validations_to_fail(["bogus"])

        expect(progress.string).to match(/\[FAIL\].*bogus/)
        expect(progress.string).to include("Invalid validation 'bogus'")
      end
    end

    context "with a passing config validation" do
      let(:config) do
        instance_double(Config, apps: { "app-one": {}, "app-two": {} }, validate_deploy_orders!: nil)
      end

      it "reports the validation as passing" do
        service.run_validations(["config"])

        expect(progress.string).to match(/\[PASS\].*config/)
      end

      it "prints nothing when silent_if_passing is set" do
        service.run_validations(["config"], silent_if_passing: true)

        expect(progress.string).to be_empty
      end
    end

    context "when an app name prefixes another app name" do
      let(:config) do
        instance_double(
          Config,
          apps: {
            app: { match_if_app_name_starts_with: true },
            "app-staging": {}
          },
          validate_deploy_orders!: nil
        )
      end

      it "fails the config validation and exits" do
        expect_validations_to_fail(["config"])

        expect(progress.string).to match(/\[FAIL\].*config/)
        expect(progress.string).to include("'app' is a prefix of 'app-staging'")
      end
    end

    context "when the deploy order is invalid" do
      let(:config) { instance_double(Config, apps: { "app-one": {} }) }

      it "fails the config validation and exits" do
        allow(config).to receive(:validate_deploy_orders!).and_raise(RuntimeError, "Invalid deploy order")

        expect_validations_to_fail(["config"])

        expect(progress.string).to match(/\[FAIL\].*config/)
        expect(progress.string).to include("ERROR: Invalid deploy order")
      end
    end
  end

  describe "#validate_templates" do
    let(:playground) { Pathname.new(Dir.mktmpdir("cpflow-doctor-service")) }
    let(:parser) do
      instance_double(TemplateParser, template_dir: playground.to_s, deprecated_variables: {})
    end
    let(:config) { instance_double(Config, args: []) }

    before do
      allow(TemplateParser).to receive(:new).with(command).and_return(parser)
      allow(parser).to receive(:template_filename) { |name| "#{playground}/#{name}.yml" }
    end

    after do
      FileUtils.remove_entry(playground.to_s) if playground.exist?
    end

    def write_template(name)
      File.write(playground.join("#{name}.yml"), "kind: gvc\nname: #{name}\n")
    end

    context "with template names passed as args" do
      let(:config) { instance_double(Config, args: %w[app rails]) }

      it "parses the requested templates and passes" do
        write_template("app")
        write_template("rails")
        allow(parser).to receive(:parse)
          .with(["#{playground}/app.yml", "#{playground}/rails.yml"])
          .and_return([{ "kind" => "gvc", "name" => "app" }, { "kind" => "workload", "name" => "rails" }])

        service.run_validations(["templates"])

        expect(progress.string).to match(/\[PASS\].*templates/)
      end

      it "fails when a requested template file is missing" do
        write_template("app")
        allow(parser).to receive(:parse)

        expect_validations_to_fail(["templates"])

        expect(progress.string).to match(/\[FAIL\].*templates/)
        expect(progress.string).to include("Missing templates:")
        expect(progress.string).to include("- rails (#{playground}/rails.yml)")
        expect(parser).not_to have_received(:parse)
      end

      it "fails when templates are duplicated" do
        write_template("app")
        write_template("rails")
        allow(parser).to receive(:parse).and_return(
          [{ "kind" => "gvc", "name" => "app" }, { "kind" => "gvc", "name" => "app" }]
        )

        expect_validations_to_fail(["templates"])

        expect(progress.string).to match(/\[FAIL\].*templates/)
        expect(progress.string).to include("Duplicate templates found")
        expect(progress.string).to include("- kind: gvc, name: app")
      end

      it "warns about deprecated template variables without failing" do
        write_template("app")
        write_template("rails")
        allow(parser).to receive_messages(
          parse: [{ "kind" => "gvc", "name" => "app" }],
          deprecated_variables: { "APP_ORG" => "{{APP_ORG}}" }
        )

        service.run_validations(["templates"])

        expect(progress.string).to include("DEPRECATED:")
        expect(progress.string).to include("- APP_ORG -> {{APP_ORG}}")
        expect(progress.string).to match(/\[PASS\].*templates/)
      end
    end

    context "without args and without a current app" do
      it "fails asking for an app" do
        allow(config).to receive(:current).and_return(nil)

        expect_validations_to_fail(["templates"])

        expect(progress.string).to include("Can't find current config, please specify an app.")
      end
    end

    context "without args and without configured setup_app_templates" do
      it "validates every template in the template directory" do
        write_template("app")
        write_template("rails")
        allow(config).to receive(:current).and_return({ setup_app_templates: nil })
        parsed_filenames = nil
        allow(parser).to receive(:parse) do |filenames|
          parsed_filenames = filenames
          [{ "kind" => "gvc", "name" => "app" }]
        end

        service.run_validations(["templates"])

        expect(parsed_filenames).to contain_exactly("#{playground}/app.yml", "#{playground}/rails.yml")
        expect(progress.string).to match(/\[PASS\].*templates/)
      end
    end

    context "without args and with configured setup_app_templates" do
      it "validates only the configured subset without duplicates" do
        write_template("app")
        write_template("rails")
        allow(config).to receive(:current).and_return({ setup_app_templates: %w[app app] })
        allow(parser).to receive(:parse)
          .with(["#{playground}/app.yml"])
          .and_return([{ "kind" => "gvc", "name" => "app" }])

        service.run_validations(["templates"])

        expect(progress.string).to match(/\[PASS\].*templates/)
      end
    end
  end
end
