# frozen_string_literal: true

require_relative "definition_cache"

module Jev
  Definition = Data.define(:name, :type, :instructions, :choices, :levels) do
    def self.build(name:, instructions:, choices: nil, levels: nil)
      instructions = instructions.to_s.dup.freeze
      raise ArgumentError, "cannot use choices: and levels: together" if choices && levels

      new(name: name.to_sym, instructions: instructions, **typed_fields(choices, levels))
    end

    def simple_noul?
      type == :noul
    end

    def public_value
      simple_noul? ? instructions : self
    end

    def level_names
      compiled_fields[:names]&.dup
    end

    def level_descriptions
      compiled_fields[:descriptions]&.dup
    end

    def to_question
      question = { "type" => type.to_s, "instructions" => instructions }
      criteria = question_criteria
      question["criteria"] = criteria if criteria
      question
    end

    def self.typed_fields(choices, levels)
      if choices
        { type: :choice, choices: normalize_choices(choices), levels: nil }
      elsif levels
        { type: :score, levels: normalize_levels(levels), choices: nil }
      else
        { type: :noul, choices: nil, levels: nil }
      end
    end
    private_class_method :typed_fields

    def self.normalize_choices(choices)
      raise ArgumentError, "choices must be a Hash" unless choices.is_a?(Hash)
      raise ArgumentError, "choices cannot be empty" if choices.empty?
      raise ArgumentError, "choices must have at most 255 entries" if choices.size > 255

      unique_keys(choices, "choice").freeze
    end
    private_class_method :normalize_choices

    def self.normalize_levels(levels)
      raise ArgumentError, "levels must be a Hash" unless levels.is_a?(Hash)
      raise ArgumentError, "levels must have at least 2 entries" if levels.size < 2
      raise ArgumentError, "levels must have at most 10 entries" if levels.size > 10

      unique_keys(levels, "level").freeze
    end
    private_class_method :normalize_levels

    def self.unique_keys(pairs, label)
      seen = {}
      pairs.each do |key, description|
        symbol = normalize_key(key, label)
        raise ArgumentError, "duplicate #{label} key: #{symbol.inspect}" if seen.key?(symbol)

        seen[symbol] = description.to_s.dup.freeze
      end
      seen
    end
    private_class_method :unique_keys

    def self.normalize_key(key, label)
      raise ArgumentError, "invalid #{label} key: #{key.inspect}" unless key.is_a?(Symbol) || key.is_a?(String)
      raise ArgumentError, "invalid #{label} key: #{key.inspect}" if key.to_s.empty?

      key.to_sym
    end
    private_class_method :normalize_key

    private

    def compiled_fields
      DefinitionCache.fetch(self)
    end

    def question_criteria
      compiled_fields[:criteria]&.dup
    end
  end
end
