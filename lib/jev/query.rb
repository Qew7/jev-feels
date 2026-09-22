# frozen_string_literal: true

module Jev
  class Query
    attr_reader :questions

    def initialize(scope)
      @scope = scope
      @questions = {}
    end

    def feels(name, **options)
      add(name, options, :noul)
    end

    def decide(name, **options)
      add(name, options, :choice)
    end

    def score(name, **options)
      add(name, options, :score)
    end

    private

    def add(name, options, type)
      raise ArgumentError, "batch questions must be a defined Symbol" unless name.is_a?(Symbol)
      raise ArgumentError, "duplicate batch question: #{name.inspect}" if @questions.key?(name)

      definition = Jev.send(:resolve_definition, name, scope: @scope, **options)
      unless definition.type == type
        raise ArgumentError, "#{name.inspect} is a #{definition.type} definition, not a #{type}"
      end

      @questions[name] = definition
    end
  end
end
