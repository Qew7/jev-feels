# frozen_string_literal: true

module Jev
  module DefinitionCache
    EMPTY_FIELDS = { names: nil, descriptions: nil, criteria: nil }.freeze
    # Keep compiled values alive across GC without retaining every ad-hoc definition.
    LIMIT = 256

    @mutex = Mutex.new
    @fields = {}.compare_by_identity

    def self.fetch(definition)
      source = definition.choices || definition.levels
      return EMPTY_FIELDS if source.nil?
      return compile(definition) unless source.frozen?

      @mutex.synchronize do
        return @fields[definition] if @fields.key?(definition)

        fields = compile(definition)
        @fields.shift if @fields.size >= LIMIT
        @fields[definition] = fields
      end
    end

    def self.compile(definition)
      if definition.levels
        names = definition.levels.keys.freeze
        descriptions = definition.levels.values.freeze
      end
      criteria =
        case definition.type
        when :choice then definition.choices.transform_keys(&:to_s).freeze
        when :score then descriptions
        end
      { names: names, descriptions: descriptions, criteria: criteria }.freeze
    end
    private_class_method :compile
  end

  private_constant :DefinitionCache
end
