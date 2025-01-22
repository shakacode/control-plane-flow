# frozen_string_literal: true

module TerraformConfig
  class VolumeSet < Base # rubocop:disable Metrics/ClassLength
    PERFORMANCE_CLASSES = %w[general-purpose-ssd high-throughput-ssd].freeze
    FILE_SYSTEM_TYPES = %w[xfs ext4].freeze
    MIN_CAPACITY = 10
    MIN_SCALING_FACTOR = 1.1

    attr_reader :gvc, :name, :initial_capacity, :performance_class, :file_system_type,
                :storage_class_suffix, :description, :tags, :snapshots, :autoscaling

    def initialize( # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength
      gvc:,
      name:,
      initial_capacity:,
      performance_class:,
      file_system_type:,
      storage_class_suffix: nil,
      description: nil,
      tags: nil,
      snapshots: nil,
      autoscaling: nil
    )
      super()

      @gvc = gvc
      @name = name
      @initial_capacity = initial_capacity
      @performance_class = performance_class
      @file_system_type = file_system_type
      @storage_class_suffix = storage_class_suffix
      @description = description
      @tags = tags
      @snapshots = snapshots
      @autoscaling = autoscaling

      validate_attributes!
    end

    def importable?
      true
    end

    def reference
      "cpln_volume_set.#{name}"
    end

    def to_tf
      block :resource, :cpln_volume_set, name do
        base_arguments_tf
        snapshots_tf
        autoscaling_tf
      end
    end

    private

    def validate_attributes!
      validate_initial_capacity!
      validate_performance_class!
      validate_file_system_type!
      validate_autoscaling! if autoscaling
    end

    def validate_initial_capacity!
      raise ArgumentError, "Initial capacity must be numeric" unless initial_capacity.is_a?(Numeric)
      return if initial_capacity >= MIN_CAPACITY

      raise ArgumentError, "Initial capacity should be >= #{MIN_CAPACITY}"
    end

    def validate_performance_class!
      return if PERFORMANCE_CLASSES.include?(performance_class.to_s)

      raise ArgumentError,
            "Invalid performance class: #{performance_class}. Choose from #{PERFORMANCE_CLASSES.join(', ')}"
    end

    def validate_file_system_type!
      return if FILE_SYSTEM_TYPES.include?(file_system_type.to_s)

      raise ArgumentError, "Invalid file system type: #{file_system_type}. Choose from #{FILE_SYSTEM_TYPES.join(', ')}"
    end

    def validate_autoscaling!
      validate_max_capacity!
      validate_min_free_percentage!
      validate_scaling_factor!
    end

    def validate_max_capacity!
      max_capacity = autoscaling.fetch(:max_capacity, nil)
      return if max_capacity.nil?

      raise ArgumentError, "autoscaling.max_capacity must be numeric" unless max_capacity.is_a?(Numeric)
      return if max_capacity >= MIN_CAPACITY

      raise ArgumentError, "autoscaling.max_capacity should be >= #{MIN_CAPACITY}"
    end

    def validate_min_free_percentage!
      min_free_percentage = autoscaling.fetch(:min_free_percentage, nil)
      return if min_free_percentage.nil?

      raise ArgumentError, "autoscaling.min_free_percentage must be numeric" unless min_free_percentage.is_a?(Numeric)
      return if min_free_percentage.between?(1, 100)

      raise ArgumentError, "autoscaling.min_free_percentage should be between 1 and 100"
    end

    def validate_scaling_factor!
      scaling_factor = autoscaling.fetch(:scaling_factor, nil)
      return if scaling_factor.nil?

      raise ArgumentError, "autoscaling.scaling_factor must be numeric" unless scaling_factor.is_a?(Numeric)
      return if scaling_factor >= MIN_SCALING_FACTOR

      raise ArgumentError, "autoscaling.scaling_factor should be >= #{MIN_SCALING_FACTOR}"
    end

    def base_arguments_tf
      argument :gvc, gvc

      argument :name, name
      argument :description, description, optional: true
      argument :tags, tags, optional: true

      argument :initial_capacity, initial_capacity
      argument :performance_class, performance_class
      argument :storage_class_suffix, storage_class_suffix, optional: true
      argument :file_system_type, file_system_type
    end

    def snapshots_tf
      return if snapshots.nil?

      block :snapshots do
        %i[create_final_snapshot retention_duration schedule].each do |arg_name|
          argument arg_name, snapshots.fetch(arg_name, nil), optional: true
        end
      end
    end

    def autoscaling_tf
      return if autoscaling.nil?

      block :autoscaling do
        %i[max_capacity min_free_percentage scaling_factor].each do |arg_name|
          argument arg_name, autoscaling.fetch(arg_name, nil), optional: true
        end
      end
    end
  end
end
