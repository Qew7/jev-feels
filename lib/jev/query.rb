# frozen_string_literal: true

module Jev
  class Query
    attr_reader :questions

    def initialize(scope)
      @scope = scope
      @questions = {}
    end

    def feels(name, **options)
      add(name, options)
    end

    def decide(name, **options)
      add(name, options)
    end

    def score(name, **options)
      add(name, options)
    end

    private

    def add(name, options)
      raise ArgumentError, "batch questions must be a defined Symbol" unless name.is_a?(Symbol)
      raise ArgumentError, "duplicate batch question: #{name.inspect}" if @questions.key?(name)

      @questions[name] = Jev.send(:resolve_definition, name, scope: @scope, **options)
    end
  end
end
