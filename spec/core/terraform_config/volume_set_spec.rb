# frozen_string_literal: true

require "spec_helper"

describe TerraformConfig::VolumeSet do
  let(:config) { described_class.new(**options) }

  let(:options) do
    {
      gvc: "test-gvc",
      name: "test-volume-set",
      description: "Test volume set",
      tags: { "env" => "test", "project" => "example" },
      initial_capacity: 20,
      performance_class: "general-purpose-ssd",
      file_system_type: "xfs"
    }
  end

  describe "#to_tf" do
    subject(:generated) { config.to_tf }

    context "with basic configuration" do
      it "generates correct config" do
        expect(generated).to eq(
          <<~EXPECTED
            resource "cpln_volume_set" "#{options.fetch(:name)}" {
              gvc = "#{options.fetch(:gvc)}"
              name = "#{options.fetch(:name)}"
              description = "#{options.fetch(:description)}"
              tags = {
                env = "test"
                project = "example"
              }
              initial_capacity = #{options.fetch(:initial_capacity)}
              performance_class = "#{options.fetch(:performance_class)}"
              file_system_type = "#{options.fetch(:file_system_type)}"
            }
          EXPECTED
        )
      end
    end

    context "with storage_class_suffix" do
      let(:config) { described_class.new(**options.merge(storage_class_suffix: "suffix")) }

      it "includes storage_class_suffix in the config" do
        expect(generated).to include('storage_class_suffix = "suffix"')
      end
    end

    context "with snapshots" do
      let(:config) do
        described_class.new(**options.merge(
          snapshots: {
            create_final_snapshot: true,
            retention_duration: "7d",
            schedule: "0 1 * * *"
          }
        ))
      end

      it "includes snapshots block in the config" do
        expect(generated).to include(
          <<~EXPECTED.strip.indent(2)
            snapshots {
              create_final_snapshot = true
              retention_duration = "7d"
              schedule = "0 1 * * *"
            }
          EXPECTED
        )
      end
    end

    context "with autoscaling" do
      let(:config) do
        described_class.new(**options.merge(
          autoscaling: {
            max_capacity: 100,
            min_free_percentage: 20,
            scaling_factor: 1.5
          }
        ))
      end

      it "includes autoscaling block in the config" do
        expect(generated).to include(
          <<~EXPECTED.strip.indent(2)
            autoscaling {
              max_capacity = 100
              min_free_percentage = 20
              scaling_factor = 1.5
            }
          EXPECTED
        )
      end
    end
  end

  describe "validations" do
    shared_examples "an invalid parameter" do |param, value, err_msg|
      it "raises an error for invalid #{param}" do
        expect { described_class.new(**options.merge(param => value)) }.to raise_error(ArgumentError, err_msg)
      end
    end

    include_examples "an invalid parameter", :initial_capacity, 5, "Initial capacity should be >= 10"
    include_examples "an invalid parameter", :initial_capacity, "10", "Initial capacity must be numeric"

    include_examples "an invalid parameter",
                     :performance_class, "invalid",
                     "Invalid performance class: invalid. Choose from general-purpose-ssd, high-throughput-ssd"

    include_examples "an invalid parameter",
                     :file_system_type, "invalid",
                     "Invalid file system type: invalid. Choose from xfs, ext4"
  end

  describe "autoscaling validations" do
    shared_examples "invalid autoscaling parameter" do |autoscaling_options, err_msg|
      it "raises an error" do
        expect { described_class.new(**options.merge(autoscaling: autoscaling_options)) }.to raise_error(
          ArgumentError, err_msg
        )
      end
    end

    context "with invalid max_capacity" do
      include_examples "invalid autoscaling parameter", { max_capacity: 5 }, "autoscaling.max_capacity should be >= 10"

      include_examples "invalid autoscaling parameter", { max_capacity: "100" },
                       "autoscaling.max_capacity must be numeric"
    end

    context "with invalid min_free_percentage" do
      include_examples "invalid autoscaling parameter", { min_free_percentage: 0 },
                       "autoscaling.min_free_percentage should be between 1 and 100"

      include_examples "invalid autoscaling parameter", { min_free_percentage: 101 },
                       "autoscaling.min_free_percentage should be between 1 and 100"

      include_examples "invalid autoscaling parameter", { min_free_percentage: "50" },
                       "autoscaling.min_free_percentage must be numeric"
    end

    context "with invalid scaling_factor" do
      include_examples "invalid autoscaling parameter", { scaling_factor: 1.0 },
                       "autoscaling.scaling_factor should be >= 1.1"

      include_examples "invalid autoscaling parameter", { scaling_factor: "1.5" },
                       "autoscaling.scaling_factor must be numeric"
    end

    context "with valid autoscaling values" do
      let(:valid_autoscaling) do
        options.merge(
          autoscaling: {
            max_capacity: 100,
            min_free_percentage: 20,
            scaling_factor: 1.5
          }
        )
      end

      it "does not raise an error" do
        expect { described_class.new(**valid_autoscaling) }.not_to raise_error
      end
    end

    context "with partial autoscaling values" do
      let(:partial_autoscaling) do
        options.merge(
          autoscaling: {
            max_capacity: 100
          }
        )
      end

      it "does not raise an error" do
        expect { described_class.new(**partial_autoscaling) }.not_to raise_error
      end
    end
  end

  it_behaves_like "importable terraform resource", reference: "cpln_volume_set.test-volume-set"
end
