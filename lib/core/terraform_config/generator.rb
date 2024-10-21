# frozen_string_literal: true

module TerraformConfig
  class Generator
    attr_reader :config, :template

    def initialize(config:, template:)
      @config = config
      @template = template
    end

    def filename
      case template["kind"]
      when "gvc"
        "gvc.tf"
      when "identity"
        "identities.tf"
      when "secret"
        "secrets.tf"
      else
        raise "Unsupported template kind - #{template['kind']}"
      end
    end

    def tf_config
      case template["kind"]
      when "gvc"
        gvc_config
      when "identity"
        identity_config
      when "secret"
        secret_config
      else
        raise "Unsupported template kind - #{template['kind']}"
      end
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
        gvc: "cpln_gvc.#{config.app}.name", # GVC name matches application name
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
