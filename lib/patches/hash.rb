# frozen_string_literal: true

class Hash
  # Copied from Rails
  def symbolize_keys
    transform_keys { |key| key.to_sym rescue key } # rubocop:disable Style/RescueModifier
  end

  def underscore_keys
    transform_keys do |key|
      underscored = key.to_s.underscore
      key.is_a?(Symbol) ? underscored.to_sym : underscored
    rescue StandardError
      key
    end
  end
end
