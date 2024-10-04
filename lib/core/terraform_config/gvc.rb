# frozen_string_literal: true

module TerraformConfig
  class Gvc < Base
    attr_reader :name, :description, :tags, :domain, :locations, :pull_secrets, :env, :load_balancer

    # rubocop:disable Metrics/ParameterLists
    def initialize(
      name:,
      description: nil,
      tags: nil,
      domain: nil,
      locations: nil,
      pull_secrets: nil,
      env: nil,
      load_balancer: nil
    )
      super()

      @name = name
      @description = description
      @tags = tags
      @domain = domain
      @locations = locations
      @pull_secrets = pull_secrets
      @env = env
      @load_balancer = load_balancer&.transform_keys { |k| k.to_s.underscore.to_sym }
    end
    # rubocop:enable Metrics/ParameterLists

    def to_tf
      block :resource, :cpln_gvc, name do
        argument :name, name
        argument :description, description, optional: true
        argument :tags, tags, optional: true

        argument :domain, domain, optional: true
        argument :locations, locations, optional: true
        argument :pull_secrets, pull_secrets, optional: true
        argument :env, env, optional: true

        load_balancer_tf
      end
    end

    private

    def load_balancer_tf
      return if load_balancer.nil?

      block :load_balancer do
        argument :dedicated, load_balancer.fetch(:dedicated)
        argument :trusted_proxies, load_balancer.fetch(:trusted_proxies, nil), optional: true
      end
    end
  end
end
