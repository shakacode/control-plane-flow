# frozen_string_literal: true

module TerraformConfig
  class Generator
    attr_reader :config, :template

    def initialize(config:, template:)
      @config = config
      @template = template
    end

    # rubocop:disable Metrics/MethodLength
    def filename
      case template["kind"]
      when "gvc"
        "gvc.tf"
      when "secret"
        "secrets.tf"
      when "identity"
        "identities.tf"
      when "policy"
        "policies.tf"
      else
        raise "Unsupported template kind - #{template['kind']}"
      end
    end
    # rubocop:enable Metrics/MethodLength

    def tf_config
      method_name = :"#{template['kind']}_config"
      raise "Unsupported template kind - #{template['kind']}" unless self.class.private_method_defined?(method_name)

      send(method_name)
    end

    private

    # rubocop:disable Metrics/MethodLength
    def gvc_config
      pull_secrets = template.dig("spec", "pullSecretLinks")&.map do |secret_link|
        secret_name = secret_link.split("/").last
        "cpln_secret.#{secret_name}.name"
      end

      load_balancer = template.dig("spec", "loadBalancer")

      TerraformConfig::Gvc.new(
        name: template["name"],
        description: template["description"],
        tags: template["tags"],
        domain: template.dig("spec", "domain"),
        env: env,
        pull_secrets: pull_secrets,
        locations: locations,
        load_balancer: load_balancer
      )
    end
    # rubocop:enable Metrics/MethodLength

    def identity_config
      TerraformConfig::Identity.new(
        gvc: gvc,
        name: template["name"],
        description: template["description"],
        tags: template["tags"]
      )
    end

    def secret_config
      TerraformConfig::Secret.new(
        name: template["name"],
        description: template["description"],
        type: template["type"],
        data: template["data"],
        tags: template["tags"]
      )
    end

    # rubocop:disable Metrics/MethodLength
    def policy_config
      # //secret/secret-name -> secret-name
      target_links = template["targetLinks"]&.map do |target_link|
        target_link.split("/").last
      end

      # //group/viewers -> group/viewers
      bindings = template["bindings"]&.map do |data|
        principal_links = data.delete("principalLinks")&.map { |link| link.delete_prefix("//") }
        data.merge("principalLinks" => principal_links)
      end

      TerraformConfig::Policy.new(
        name: template["name"],
        description: template["description"],
        tags: template["tags"],
        target: template["target"],
        target_kind: template["targetKind"],
        target_query: template["targetQuery"],
        target_links: target_links,
        gvc: gvc,
        bindings: bindings
      )
    end
    # rubocop:enable Metrics/MethodLength

    # GVC name matches application name
    def gvc
      "cpln_gvc.#{config.app}.name"
    end

    def env
      template.dig("spec", "env").to_h { |env_var| [env_var["name"], env_var["value"]] }
    end

    def locations
      template.dig("spec", "staticPlacement", "locationLinks")&.map do |location_link|
        location_link.split("/").last
      end
    end
  end
end
