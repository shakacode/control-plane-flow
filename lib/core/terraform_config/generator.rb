# frozen_string_literal: true

module TerraformConfig
  class Generator
    attr_reader :config, :template

    def initialize(config:, template:)
      @config = config
      @template = template.deep_underscore_keys.deep_symbolize_keys
    end

    def filename # rubocop:disable Metrics/MethodLength
      case kind
      when "gvc"
        "gvc.tf"
      when "secret"
        "secrets.tf"
      when "identity"
        "identities.tf"
      when "policy"
        "policies.tf"
      else
        raise "Unsupported template kind - #{kind}"
      end
    end

    def tf_config
      method_name = :"#{kind}_config"
      raise "Unsupported template kind - #{kind}" unless self.class.private_method_defined?(method_name)

      send(method_name)
    end

    private

    def kind
      @kind ||= template[:kind]
    end

    def gvc_config # rubocop:disable Metrics/MethodLength
      TerraformConfig::Gvc.new(
        **template
          .slice(:name, :description, :tags)
          .merge(
            env: gvc_env,
            pull_secrets: gvc_pull_secrets,
            locations: gvc_locations,
            domain: template.dig(:spec, :domain),
            load_balancer: template.dig(:spec, :load_balancer)
          )
      )
    end

    def identity_config
      TerraformConfig::Identity.new(**template.slice(:name, :description, :tags).merge(gvc: gvc))
    end

    def secret_config
      TerraformConfig::Secret.new(**template.slice(:name, :description, :type, :data, :tags))
    end

    def policy_config
      TerraformConfig::Policy.new(
        **template
          .slice(:name, :description, :tags, :target, :target_kind, :target_query)
          .merge(gvc: gvc, target_links: policy_target_links, bindings: policy_bindings)
      )
    end

    # GVC name matches application name
    def gvc
      "cpln_gvc.#{config.app}.name"
    end

    def gvc_pull_secrets
      template.dig(:spec, :pull_secret_links)&.map do |secret_link|
        secret_name = secret_link.split("/").last
        "cpln_secret.#{secret_name}.name"
      end
    end

    def gvc_env
      template.dig(:spec, :env).to_h { |env_var| [env_var[:name], env_var[:value]] }
    end

    def gvc_locations
      template.dig(:spec, :static_placement, :location_links)&.map do |location_link|
        location_link.split("/").last
      end
    end

    # //secret/secret-name -> secret-name
    def policy_target_links
      template[:target_links]&.map do |target_link|
        target_link.split("/").last
      end
    end

    # //group/viewers -> group/viewers
    def policy_bindings
      template[:bindings]&.map do |data|
        principal_links = data.delete(:principal_links)&.map { |link| link.delete_prefix("//") }
        data.merge(principal_links: principal_links)
      end
    end
  end
end
