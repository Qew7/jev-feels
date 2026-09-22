# frozen_string_literal: true

module Jev
  module Result
    def self.parse(answer, definition)
      raise InvalidResponseError, "Jev response is missing an answer" unless answer.is_a?(Hash)

      case definition.type
      when :noul then Noul.parse(answer)
      when :choice then Choice.parse(answer, definition)
      when :score then Score.parse(answer, definition)
      else
        raise InvalidResponseError, "unknown Jev definition type: #{definition.type.inspect}"
      end
    end

    def self.finite_unit(value, label)
      raise InvalidResponseError, "Jev response is missing #{label}" unless value.is_a?(Numeric)

      value = Float(value)
      raise InvalidResponseError, "Jev #{label} is not finite" unless value.finite?

      value
    rescue ArgumentError, TypeError, RangeError
      raise InvalidResponseError, "Jev #{label} is not a real number"
    end

    class Noul
      attr_reader :probability

      def initialize(probability:)
        @probability = probability
        freeze
      end

      def self.parse(answer)
        noul = answer["noul"]
        raise InvalidResponseError, "Jev response is missing a noul probability" unless noul.is_a?(Numeric)

        noul = Float(noul)
        raise InvalidResponseError, "Jev noul probability is not finite" unless noul.finite?

        # ponytail: clamp out-of-range noul; raise if Jev starts returning uncalibrated values
        new(probability: noul.clamp(0.0, 1.0))
      end

      def type
        :noul
      end

      def collapsed(threshold: 0.5)
        probability >= threshold
      end
    end

    class Choice
      attr_reader :choice, :confidence, :probabilities

      def initialize(choice:, confidence:, probabilities:)
        @choice = choice
        @confidence = confidence
        @probabilities = probabilities
        freeze
      end

      def self.parse(answer, definition = nil)
        winner = choice_key(answer["choice"], definition)
        new(
          choice: winner,
          confidence: Result.finite_unit(answer["confidence"], "choice confidence").clamp(0.0, 1.0),
          probabilities: choice_probabilities(answer["probabilities"], definition)
        )
      end

      def self.choice_key(key, definition)
        unless key.is_a?(String) || key.is_a?(Symbol)
          raise InvalidResponseError, "Jev response is missing a valid choice"
        end
        if definition && !definition.choices.key?(key.to_sym)
          raise InvalidResponseError, "Jev response has an unknown choice"
        end

        key.to_sym
      end
      private_class_method :choice_key

      def self.choice_probabilities(raw, definition)
        raise InvalidResponseError, "Jev response is missing choice probabilities" unless raw.is_a?(Hash)

        raw.to_h do |key, value|
          [choice_key(key, definition), Result.finite_unit(value, "choice probability")]
        end.freeze
      end
      private_class_method :choice_probabilities

      def type
        :choice
      end

      def collapsed(*)
        choice
      end
    end

    class Score
      attr_reader :score, :confidence, :probabilities, :levels, :level

      def initialize(score:, confidence:, probabilities:, levels:, level:)
        @score = score
        @confidence = confidence
        @probabilities = probabilities
        @levels = levels
        @level = level
        freeze
      end

      def self.parse(answer, definition)
        names = definition.level_names
        probabilities = score_probabilities(answer["probabilities"], names)
        score = Result.finite_unit(answer["score"], "score")
        new(
          score: score,
          confidence: Result.finite_unit(answer["confidence"], "score confidence").clamp(0.0, 1.0),
          probabilities: probabilities,
          levels: definition.levels,
          level: named_level(probabilities, names)
        )
      end

      def self.score_probabilities(raw, names)
        raise InvalidResponseError, "Jev response is missing score probabilities" unless raw.is_a?(Hash)

        raw.to_h do |key, value|
          index = level_index(key, names)
          [names ? names.fetch(index) : index, Result.finite_unit(value, "score probability")]
        end.freeze
      end

      def self.level_index(key, names)
        index = parse_index(key)
        if index.negative? || (names && index >= names.size)
          raise InvalidResponseError, "Jev score probability has an unknown level"
        end

        index
      end
      private_class_method :level_index

      def self.parse_index(key)
        return key if key.is_a?(Integer)
        unless key.is_a?(String) && key.match?(/\A\d+\z/)
          raise InvalidResponseError, "Jev score probabilities are not keyed by level number"
        end

        Integer(key, 10)
      end
      private_class_method :parse_index

      def self.named_level(probabilities, names)
        return unless names

        key, = probabilities.max_by { |_, weight| weight }
        key if key.is_a?(Symbol)
      end
      private_class_method :named_level

      def type
        :score
      end

      def collapsed(*)
        score
      end
    end

    class Batch
      def initialize(results)
        @results = results.transform_keys(&:to_sym).freeze
        freeze
      end

      def [](key)
        @results[key.to_sym]
      end

      def to_h
        @results.transform_values(&:collapsed)
      end

      def deconstruct_keys(keys)
        return to_h unless keys

        keys.each_with_object({}) do |key, values|
          symbol = key.to_sym
          values[symbol] = @results.fetch(symbol).collapsed if @results.key?(symbol)
        end
      end

      def type
        :batch
      end
    end
  end
end
