# frozen_string_literal: true

module Command
  class Exist < Base
    def call
      exit(!cp.gvc_get.nil?)
    end
  end
end
