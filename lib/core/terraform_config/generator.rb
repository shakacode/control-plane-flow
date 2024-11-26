# frozen_string_literal: true

module TerraformConfig
  class Generator # rubocop:disable Metrics/ClassLength
    SUPPORTED_TEMPLATE_KINDS = %w[gvc secret identity policy volumeset workload auditctx agent].freeze
    WORKLOAD_SPEC_KEYS = %i[
      type
      containers
      default_options
      local_options
      rollout_options
      security_options
      load_balancer
      firewall_config
      support_dynamic_tags
      job
    ].freeze

    class InvalidTemplateError < ArgumentError; end

    attr_reader :config, :template

    def initialize(config:, template:)
      @config = config
      @template = template.deep_underscore_keys.deep_symbolize_keys
      validate_template_kind!
    end

    def tf_configs
      tf_config.locals.merge(filename => tf_config)
    end

    private

    def validate_template_kind!
      return if SUPPORTED_TEMPLATE_KINDS.include?(kind)

      raise InvalidTemplateError, "Unsupported template kind: #{kind}"
    end

    def filename
      case kind
      when "gvc"
        "gvc.tf"
      when "workload"
        "#{template[:name]}.tf"
      when "auditctx"
        "audit_contexts.tf"
      else
        "#{kind.pluralize}.tf"
      end
    end

    def tf_config
      @tf_config ||= config_class.new(**config_params)
    end

    def config_class
      case kind
      when "volumeset"
        TerraformConfig::VolumeSet
      when "auditctx"
        TerraformConfig::AuditContext
      else
        TerraformConfig.const_get(kind.capitalize)
      end
    end

    def config_params
      send("#{kind}_config_params")
    end

    def gvc_config_params
      template
        .slice(:name, :description, :tags)
        .merge(
          env: gvc_env,
          pull_secrets: gvc_pull_secrets,
          locations: gvc_locations,
          domain: template.dig(:spec, :domain),
          load_balancer: template.dig(:spec, :load_balancer)
        )
    end

    def identity_config_params
      template.slice(:name, :description, :tags).merge(gvc: gvc)
    end

    def secret_config_params
      template.slice(:name, :description, :type, :data, :tags)
    end

    def policy_config_params
      template
        .slice(:name, :description, :tags, :target, :target_kind, :target_query)
        .merge(gvc: gvc, target_links: policy_target_links, bindings: policy_bindings)
    end

    def volumeset_config_params
      specs = %i[
        initial_capacity
        performance_class
        file_system_type
        storage_class_suffix
        snapshots
        autoscaling
      ].to_h { |key| [key, template.dig(:spec, key)] }

      template.slice(:name, :description, :tags).merge(gvc: gvc).merge(specs)
    end

    def auditctx_config_params
      template.slice(:name, :description, :tags)
    end

    def agent_config_params
      template.slice(:name, :description, :tags)
    end

    def workload_config_params
      template
        .slice(:name, :description, :tags)
        .merge(gvc: gvc, identity: workload_identity)
        .merge(workload_spec_params)
    end

    def workload_spec_params # rubocop:disable Metrics/MethodLength
      WORKLOAD_SPEC_KEYS.to_h do |key|
        arg_name =
          case key
          when :default_options then :options
          when :firewall_config then :firewall_spec
          else key
          end

        value = template.dig(:spec, key)

        if value
          case key
          when :local_options
            value[:location] = value.delete(:location).split("/").last
          when :security_options
            value[:file_system_group_id] = value.delete(:filesystem_group_id)
          end
        end

        [arg_name, value]
      end
    end

    # GVC name matches application name
    def gvc
      "cpln_gvc.#{config.app}.name"
    end

    def gvc_pull_secrets
      template.dig(:spec, :pull_secret_links)&.map { |secret_link| "cpln_secret.#{secret_link.split('/').last}.name" }
    end

    def gvc_env
      template.dig(:spec, :env).to_h { |env_var| [env_var[:name], env_var[:value]] }
    end

    def gvc_locations
      template.dig(:spec, :static_placement, :location_links)&.map { |location_link| location_link.split("/").last }
    end

    def policy_target_links
      template[:target_links]&.map { |target_link| target_link.split("/").last }
    end

    def policy_bindings
      template[:bindings]&.map do |data|
        principal_links = data.delete(:principal_links)&.map { |link| link.delete_prefix("//") }
        data.merge(principal_links: principal_links)
      end
    end

    def workload_identity
      identity_link = template.dig(:spec, :identity_link)
      return if identity_link.nil?

      "cpln_identity.#{identity_link.split('/').last}"
    end

    def kind
      @kind ||= template[:kind]
    end
  end
end
