# frozen_string_literal: true

module TerraformConfig
  class Workload < Base
    RAW_ARGS = %i[
      containers options local_options rollout_options security_options
      firewall_spec load_balancer job
    ].freeze

    OPTIONS_KEYS = %i[autoscaling capacity_ai suspend timeout_seconds].freeze
    LOCAL_OPTIONS_KEYS = (OPTIONS_KEYS + %i[location]).freeze
    ROLLOUT_OPTIONS_KEYS = %i[max_surge_replicas min_ready_seconds].freeze
    SECURITY_OPTIONS_KEYS = %i[filesystem_group_id].freeze
    LOAD_BALANCER_KEYS = %i[direct geo_location].freeze
    FIREWALL_SPEC_KEYS = %i[internal external].freeze
    VOLUME_KEYS = %i[uri path].freeze
    JOB_KEYS = %i[schedule concurrency_policy history_limit restart_policy active_deadline_seconds].freeze
    LIVENESS_PROBE_KEYS = %i[
      exec http_get tcp_socket grpc
      failure_threshold initial_delay_seconds period_seconds success_threshold timeout_seconds
    ].freeze

    attr_reader :type, :name, :gvc, :containers,
                :description, :tags, :support_dynamic_tags, :firewall_spec, :identity,
                :options, :local_options, :rollout_options, :security_options, :load_balancer, :job

    def initialize( # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength
      type:,
      gvc:,
      name:,
      containers:,
      description: nil,
      tags: nil,
      support_dynamic_tags: false,
      firewall_spec: nil,
      identity: nil,
      options: nil,
      local_options: nil,
      rollout_options: nil,
      security_options: nil,
      load_balancer: nil,
      job: nil
    )
      super()

      @type = type
      @gvc = gvc

      @name = name
      @description = description
      @tags = tags

      @containers = containers
      @firewall_spec = firewall_spec
      @identity = identity

      @options = options
      @local_options = local_options
      @rollout_options = rollout_options
      @security_options = security_options

      @load_balancer = load_balancer
      @support_dynamic_tags = support_dynamic_tags
      @job = job
    end

    def to_tf
      block :module, name do
        argument :source, "../workload"

        argument :type, type
        argument :name, name
        argument :gvc, gvc
        argument :identity, identity, optional: true
        argument :support_dynamic_tags, support_dynamic_tags, optional: true

        RAW_ARGS.each { |arg_name| argument arg_name, send(:"#{arg_name}_arg"), raw: true, optional: true }
      end
    end

    def locals
      containers.reduce({}) do |result, container|
        envs = container[:env].to_h { |env_var| [env_var[:name], env_var[:value]] }
        next result if envs.empty?

        envs_name = :"#{container.fetch(:name)}_envs"
        result.merge("#{envs_name}.tf" => LocalVariable.new(envs_name => envs))
      end
    end

    private

    def containers_arg
      containers.reduce({}) { |result, container| result.merge(container_args(container)) }.crush
    end

    def container_args(container) # rubocop:disable Metrics/MethodLength
      container_name = container.fetch(:name)

      args = container.slice(:args, :command, :image, :cpu, :memory).merge(
        post_start: container.dig(:lifecycle, :post_start, :exec, :command),
        pre_stop: container.dig(:lifecycle, :pre_stop, :exec, :command),
        inherit_env: container.fetch(:inherit_env, nil),
        envs: "local.#{container_name}_envs",
        ports: container.fetch(:ports, nil),
        readiness_probe: container.fetch(:readiness_probe, nil)&.slice(*LIVENESS_PROBE_KEYS),
        liveness_probe: container.fetch(:liveness_probe, nil)&.slice(*LIVENESS_PROBE_KEYS),
        volumes: container.fetch(:volumes, nil)&.map { |volume| volume.slice(*VOLUME_KEYS) }
      )

      { container_name => args }
    end

    RAW_ARGS.each do |spec|
      next if spec == :containers

      define_method("#{spec}_arg") do
        return if send(spec).nil?

        send(spec).slice(*self.class.const_get("#{spec.upcase}_KEYS"))
      end
    end
  end
end
