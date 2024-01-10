# frozen_string_literal: true

module DateTimeHelpers
  module_function

  def travel_to_days_later(days)
    current_date = Time.now
    target_date = current_date + (days * 24 * 60 * 60)

    Timecop.freeze(target_date)
  end

  def travel_back
    Timecop.return
  end
end
