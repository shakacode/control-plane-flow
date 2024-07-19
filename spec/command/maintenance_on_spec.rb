# frozen_string_literal: true

require "spec_helper"

describe Command::MaintenanceOn do
  it_behaves_like "switches maintenance mode command", action: :on
end
