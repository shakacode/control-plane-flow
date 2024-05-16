# frozen_string_literal: true

class ValidationError < StandardError; end

class DoctorService
  attr_reader :config

  def initialize(config)
    @config = config
  end

  def run_validations(validations, silent_if_passing: false) # rubocop:disable Metrics/MethodLength
    @any_failed_validation = false

    validations.each do |validation|
      case validation
      else
        raise ValidationError, Shell.color("ERROR: Invalid validation '#{validation}'.", :red)
      end

      progress.puts("#{Shell.color('[PASS]', :green)} #{validation}") unless silent_if_passing
    rescue ValidationError => e
      @any_failed_validation = true

      progress.puts("#{Shell.color('[FAIL]', :red)} #{validation}\n\n#{e.message}\n\n")
    end

    exit(ExitCode::ERROR_DEFAULT) if @any_failed_validation
  end

  private

  def progress
    $stderr
  end
end
