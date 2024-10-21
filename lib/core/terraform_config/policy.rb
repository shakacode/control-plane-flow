# frozen_string_literal: true

module TerraformConfig
  class Policy < Base # rubocop:disable Metrics/ClassLength
    TARGET_KINDS = %w[
      agent auditctx cloudaccount domain group gvc identity image ipset kubernetes location
      org policy quota secret serviceaccount task user volumeset workload
    ].freeze

    GVC_REQUIRED_TARGET_KINDS = %w[identity workload volumeset].freeze

    attr_reader :name, :description, :tags, :target_kind, :gvc, :target, :target_links, :target_query, :bindings

    def initialize( # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength
      name:,
      description: nil,
      tags: nil,
      target_kind: nil,
      gvc: nil,
      target: nil,
      target_links: nil,
      target_query: nil,
      bindings: nil
    )
      super()

      @name = name
      @description = description
      @tags = tags

      @target_kind = target_kind
      validate_target_kind!

      @gvc = gvc
      validate_gvc!

      @target = target
      @target_links = target_links

      @target_query = target_query&.deep_underscore_keys&.deep_symbolize_keys
      @bindings = bindings&.map { |data| data.deep_underscore_keys.deep_symbolize_keys }
    end

    def to_tf
      block :resource, :cpln_policy, name do
        argument :name, name

        %i[description tags target_kind gvc target target_links].each do |arg_name|
          argument arg_name, send(arg_name), optional: true
        end

        bindings_tf
        target_query_tf
      end
    end

    private

    def validate_target_kind!
      return if target_kind.nil? || TARGET_KINDS.include?(target_kind.to_s)

      raise ArgumentError, "Invalid target kind given - #{target_kind}"
    end

    def validate_gvc!
      return unless GVC_REQUIRED_TARGET_KINDS.include?(target_kind.to_s) && gvc.nil?

      raise ArgumentError, "`gvc` is required for `#{target_kind}` target kind"
    end

    def bindings_tf
      return if bindings.nil?

      bindings.each do |binding_data|
        block :binding do
          argument :permissions, binding_data.fetch(:permissions, nil), optional: true
          argument :principal_links, binding_data.fetch(:principal_links, nil), optional: true
        end
      end
    end

    def target_query_tf
      return if target_query.nil?

      fetch_type = target_query.fetch(:fetch, nil)
      validate_fetch_type!(fetch_type) if fetch_type

      block :target_query do
        argument :fetch, fetch_type, optional: true
        target_query_spec_tf
      end
    end

    def validate_fetch_type!(fetch_type)
      return if %w[links items].include?(fetch_type.to_s)

      raise ArgumentError, "Invalid fetch type - #{fetch_type}. Should be either `links` or `items`"
    end

    def target_query_spec_tf
      spec = target_query.fetch(:spec, nil)
      return if spec.nil?

      match_type = spec.fetch(:match, nil)
      validate_match_type!(match_type) if match_type

      block :spec do
        argument :match, match_type, optional: true

        target_query_spec_terms_tf(spec)
      end
    end

    def validate_match_type!(match_type)
      return if %w[all any none].include?(match_type.to_s)

      raise ArgumentError, "Invalid match type - #{match_type}. Should be either `all`, `any` or `none`"
    end

    def target_query_spec_terms_tf(spec)
      terms = spec.fetch(:terms, nil)
      return if terms.nil?

      terms.each do |term|
        validate_term!(term)

        block :terms do
          %i[op property rel tag value].each do |arg_name|
            argument arg_name, term.fetch(arg_name, nil), optional: true
          end
        end
      end
    end

    def validate_term!(term)
      return unless (%i[property rel tag] & term.keys).count > 1

      raise ArgumentError,
            "Each term in `target_query.spec.terms` must contain exactly one of the following attributes: " \
            "`property`, `rel`, or `tag`."
    end
  end
end
