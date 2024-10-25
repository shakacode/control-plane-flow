# frozen_string_literal: true

class Hash
  # Copied from Rails
  def deep_symbolize_keys
    deep_transform_keys { |key| key.to_sym rescue key } # rubocop:disable Style/RescueModifier
  end

  def deep_underscore_keys
    deep_transform_keys do |key|
      underscored = key.to_s.underscore
      key.is_a?(Symbol) ? underscored.to_sym : underscored
    rescue StandardError
      key
    end
  end

  def crush
    crushed = each_with_object({}) do |(key, value), hash|
      crushed_value = value.crush
      hash[key] = crushed_value unless crushed_value.nil?
    end

    crushed unless crushed.empty?
  end

  private

  # Copied from Rails
  def deep_transform_keys(&block)
    deep_transform_keys_in_object(self, &block)
  end

  # Copied from Rails
  def deep_transform_keys_in_object(object, &block)
    case object
    when Hash
      object.each_with_object(self.class.new) do |(key, value), result|
        result[yield(key)] = deep_transform_keys_in_object(value, &block)
      end
    when Array
      object.map { |e| deep_transform_keys_in_object(e, &block) }
    else
      object
    end
  end
end
