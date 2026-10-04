# frozen_string_literal: true

# Ownership is asserted only by opted-in templates creating new resources. Names
# locate candidates; the marker, shape and exact policy scope authorize cleanup.
class DisposablePostgresHelpers # rubocop:disable Metrics/ClassLength
  TAG = "cpflow-disposable-postgres-app"

  def initialize(config, controlplane)
    @config = config
    @cp = controlplane
  end

  def prepare_templates!(templates) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    marked = templates.select { |template| marked?(template) }
    return if marked.empty?

    unless disposable?
      marked.each { |template| template["tags"].delete(TAG) }
      return
    end
    candidates = templates.select { |template| resource_types.key?(template.values_at("kind", "name")) }
    refuse! unless (candidates + fetch_resources).all? { |resource| owned?(resource) }
    refuse! if shared? || externally_shared?
  end

  def validate! # rubocop:disable Metrics/CyclomaticComplexity
    return [] unless disposable?

    resources = fetch_resources
    # Legacy templates did not assert ownership. Preserve them without adoption.
    return [] unless resources.any? { |resource| marked?(resource) }

    refuse! unless resources.all? { |resource| owned?(resource) }
    refuse! if shared? || externally_shared?
    resources
  end

  def delete(&operation)
    # Remove access before secrets. Surviving marked secrets can be cleaned up
    # after a failure even when the policy or GVC no longer exists.
    validate!.sort_by { |resource| resource["kind"] == "policy" ? 0 : 1 }.each do |resource|
      current = validate!.find { |item| item["name"] == resource["name"] }
      next unless current

      kind, name = current.values_at("kind", "name")
      operation.call(kind, name) { kind == "policy" ? @cp.delete_policy(name) : @cp.delete_secret(name) }
    end
  end

  private

  def disposable?
    !@config.disposable_review_secret_resource_names.nil?
  end

  def marked?(resource)
    resource["tags"].is_a?(Hash) && resource["tags"].key?(TAG)
  end

  def fetch_resources
    resource_types.filter_map do |(kind, name), _type|
      resource = fetch(kind, name)
      resource&.merge("kind" => kind)
    end
  end

  def shared?
    names = resource_types.keys.map(&:last)
    @config.shared_secret_grants.any? do |grant|
      [grant[:secret_name], grant[:policy_name]].any? { |name| names.include?(name) }
    end
  end

  def externally_shared? # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    @cp.fetch_policies.fetch("items").any? do |policy|
      next false if policy["name"] == "#{@config.app}-pg-access" || policy["targetKind"] != "secret"

      links = policy["targetLinks"]
      next true unless links.is_a?(Array) && links.any? && policy["targetQuery"].nil? && policy["target"].nil?

      names = ["#{@config.app}-pg", "#{@config.app}-pg-script"]
      names.any? do |name|
        links.intersect?(["//secret/#{name}", "/org/#{@config.org}/secret/#{name}"])
      end
    end
  end

  def resource_types
    app = @config.app
    { ["secret", "#{app}-pg"] => "dictionary", ["secret", "#{app}-pg-script"] => "opaque",
      ["policy", "#{app}-pg-access"] => nil }
  end

  def fetch(kind, name)
    kind == "policy" ? @cp.fetch_policy(name) : @cp.fetch_secret(name)
  end

  def owned?(resource)
    key = resource.values_at("kind", "name")
    tags = resource["tags"]
    return false unless resource_types.key?(key) && tags.is_a?(Hash) && tags[TAG] == @config.app

    resource["kind"] == "secret" ? resource["type"] == resource_types[key] : policy_owned?(resource)
  end

  def policy_owned?(policy)
    return false unless policy["targetKind"] == "secret" &&
                        %w[target targetQuery gvc].all? { |key| policy[key].nil? }

    targets_owned?(policy["targetLinks"]) && bindings_owned?(policy["bindings"])
  end

  def targets_owned?(links)
    names = ["#{@config.app}-pg", "#{@config.app}-pg-script"]
    links.is_a?(Array) && links.size == 2 && names.all? do |name|
      links.one? { |link| ["//secret/#{name}", "/org/#{@config.org}/secret/#{name}"].include?(link) }
    end
  end

  def bindings_owned?(bindings)
    return false unless bindings.is_a?(Array)

    principals = [@config.identity, "#{@config.app}-pg-identity"].flat_map do |identity|
      path = "gvc/#{@config.app}/identity/#{identity}"
      ["//#{path}", "/org/#{@config.org}/#{path}"]
    end
    bindings.all? { |binding| binding_owned?(binding, principals) }
  end

  def binding_owned?(binding, principals)
    return false unless binding.is_a?(Hash) && (binding.keys - %w[permissions principalLinks]).empty?

    permissions, links = binding.values_at("permissions", "principalLinks")
    permissions.is_a?(Array) && (permissions - ["reveal"]).empty? &&
      links.is_a?(Array) && (links - principals).empty?
  end

  def refuse!
    raise "PostgreSQL helper resources have unexpected ownership, grants, or target; leaving them for inspection."
  end
end
