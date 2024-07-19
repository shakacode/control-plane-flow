# frozen_string_literal: true

require "spec_helper"

describe Command::MaintenanceOff do
  it_behaves_like "switches maintenance mode command", action: :off
end
