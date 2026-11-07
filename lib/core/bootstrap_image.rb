# frozen_string_literal: true

# An explicit build result may initialize placeholders, never replace a deployed image.
class BootstrapImage
  def self.resolve(config, controlplane, preserving:)
    image = config.options[:bootstrap_image]
    return unless image

    raise "--bootstrap-image requires runtime preservation or --refresh-templates." unless preserving

    name = image.delete_prefix("/org/#{config.org}/image/")
    unless name.match?(/\A#{Regexp.escape(config.app)}:[0-9]+_[a-f0-9]{40}\z/)
      raise "Bootstrap image must belong to this app and carry a full commit SHA."
    end

    details = controlplane.fetch_image_details(name)
    raise "Bootstrap image does not exist in this org's registry." unless details && details["name"] == name

    image
  end
end
