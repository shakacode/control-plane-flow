# frozen_string_literal: true

module VerifiedDouble
  CLASS_EQUIVALENCE_FUNCTIONS = %i[is_a? kind_of? instance_of?].freeze

  def verified_double(klass, *args)
    instance_double(klass, *args).tap do |dbl|
      CLASS_EQUIVALENCE_FUNCTIONS.each do |fn|
        allow(dbl).to receive(fn) do |*fn_args|
          klass.allocate.send(fn, *fn_args)
        end
      end
      allow(klass).to receive(:===).and_call_original
      allow(klass).to receive(:===).with(dbl).and_return true
    end
  end
end
