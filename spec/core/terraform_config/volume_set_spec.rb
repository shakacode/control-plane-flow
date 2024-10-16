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
    context "with invalid initial_capacity" do
      it "raises an error" do
        expect { described_class.new(**options.merge(initial_capacity: 5)) }.to raise_error(
          ArgumentError, "Initial capacity should be greater than or equal to 10"
        )
      end
    end

    context "with invalid performance_class" do
      it "raises an error" do
        expect { described_class.new(**options.merge(performance_class: "invalid")) }.to raise_error(
          ArgumentError, "Invalid performance class: invalid. Choose from general-purpose-ssd, high-throughput-ssd"
        )
      end
    end

    context "with invalid file_system_type" do
      it "raises an error" do
        expect { described_class.new(**options.merge(file_system_type: "invalid")) }.to raise_error(
          ArgumentError, "Invalid file system type: invalid. Choose from xfs, ext4"
        )
      end
    end
  end

  describe "autoscaling validations" do
    context "with invalid max_capacity" do
      let(:invalid_autoscaling) do
        options.merge(autoscaling: { max_capacity: 5 })
      end

      it "raises an error" do
        expect { described_class.new(**invalid_autoscaling) }.to raise_error(
          ArgumentError, "autoscaling.max_capacity should be >= 10"
        )
      end
    end

    context "with invalid min_free_percentage" do
      let(:invalid_autoscaling) do
        options.merge(autoscaling: { min_free_percentage: 0 })
      end

      it "raises an error for value below 1" do
        expect { described_class.new(**invalid_autoscaling) }.to raise_error(
          ArgumentError, "autoscaling.min_free_percentage should be between 1 and 100"
        )
      end

      it "raises an error for value above 100" do
        invalid_autoscaling[:autoscaling][:min_free_percentage] = 101
        expect { described_class.new(**invalid_autoscaling) }.to raise_error(
          ArgumentError, "autoscaling.min_free_percentage should be between 1 and 100"
        )
      end
    end

    context "with invalid scaling_factor" do
      let(:invalid_autoscaling) do
        options.merge(autoscaling: { scaling_factor: 1.0 })
      end

      it "raises an error" do
        expect { described_class.new(**invalid_autoscaling) }.to raise_error(
          ArgumentError, "autoscaling.scaling_factor should be >= 1.1"
        )
      end
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
end
