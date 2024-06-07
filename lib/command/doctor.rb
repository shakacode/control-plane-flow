# frozen_string_literal: true

module Command
  class Doctor < Base
    NAME = "doctor"
    OPTIONS = [
      validations_option,
      app_option
    ].freeze
    DESCRIPTION = "Runs validations"
    LONG_DESCRIPTION = <<~DESC
      - Runs validations
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Runs all validations that don't require additional options by default.
      cpflow doctor

      # Runs config validation.
      cpflow doctor --validations config

      # Runs templates validation (requires app).
      cpflow doctor --validations templates -a $APP_NAME
      ```
    EX
    VALIDATIONS = [].freeze

    def call
      validations = config.options[:validations].split(",")
      ensure_required_options!(validations)

      doctor_service = DoctorService.new(config)
      doctor_service.run_validations(validations)
    end

    private

    def ensure_required_options!(validations)
      validations.each do |validation|
        case validation
        when "templates"
          raise "App is required for templates validation." unless config.app
        end
      end
    end
  end
end
