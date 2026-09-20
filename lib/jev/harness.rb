# frozen_string_literal: true

require "json"

module Jev
  module Harness
    THREAD_KEY = :jev_transport

    module_function

    def current_transport(configuration)
      Thread.current[THREAD_KEY] || configuration.transport || Transport.new(configuration)
    end

    def stub(answers, &)
      raise ArgumentError, "Jev.stub requires a block" unless block_given?

      overlay(StubTransport.new(answers), &)
    end

    def record(&)
      raise ArgumentError, "Jev.record requires a block" unless block_given?

      tape = Tape.new
      inner = current_transport(Jev.configuration)
      overlay(RecordingTransport.new(inner, tape), &)
      tape
    end

    def replay(tape, &)
      raise ArgumentError, "Jev.replay requires a block" unless block_given?

      tape = Tape.parse(tape) unless tape.is_a?(Tape)
      overlay(ReplayTransport.new(tape), &)
    end

    def overlay(transport)
      previous = Thread.current[THREAD_KEY]
      Thread.current[THREAD_KEY] = transport
      yield
    ensure
      Thread.current[THREAD_KEY] = previous
    end
    private_class_method :overlay

    class Tape
      def initialize(entries = [])
        @entries = entries
      end

      def record(payload, response)
        @entries << { "request" => canonical(payload), "response" => canonical(response) }
      end

      def lookup(payload)
        request = canonical(payload)
        entry = @entries.find { |item| item["request"] == request }
        raise ReplayError, replay_message(payload) unless entry

        entry["response"]
      end

      def to_json(*)
        JSON.generate({ "version" => 1, "entries" => @entries })
      end

      def self.parse(json)
        payload = json.is_a?(String) ? JSON.parse(json) : json
        raise ArgumentError, "tape is not a JSON object" unless payload.is_a?(Hash)

        entries = payload["entries"]
        raise ArgumentError, "tape is missing entries" unless entries.is_a?(Array)

        new(entries)
      end

      private

      def canonical(value)
        case value
        when Hash
          value.to_h.transform_keys(&:to_s).sort.to_h.transform_values { |item| canonical(item) }
        when Array
          value.map { |item| canonical(item) }
        else
          value
        end
      end

      def replay_message(payload)
        ids = payload.is_a?(Hash) ? payload["questions"]&.keys : nil
        "Jev replay has no recorded answer for questions #{ids.inspect}"
      end
    end

    class RecordingTransport
      def initialize(inner, tape)
        @inner = inner
        @tape = tape
      end

      def call(payload)
        response = @inner.call(payload)
        @tape.record(payload, response)
        response
      end
    end

    class ReplayTransport
      def initialize(tape)
        @tape = tape
      end

      def call(payload)
        @tape.lookup(payload)
      end
    end

    class StubTransport
      def initialize(answers)
        @answers = answers.to_h.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }
      end

      def call(payload)
        questions = payload.fetch("questions")
        {
          "answers" => questions.to_h { |id, question| [id, answer_for(id, question)] }
        }
      end

      private

      def answer_for(id, question)
        stub = @answers[id.to_sym] || @answers[Jev.send(:name_for_instructions, question["instructions"])]
        raise ArgumentError, "unstubbed Jev question: #{id}" if stub.nil?

        case question["type"]
        when "noul" then noul_answer(stub)
        when "choice" then choice_answer(stub, question)
        when "score" then score_answer(stub, question)
        else
          raise ArgumentError, "unstubbed Jev question: #{id}"
        end
      end

      def noul_answer(stub)
        noul = stub.is_a?(Hash) ? stub[:noul] || stub["noul"] || stub[:probability] : stub
        { "type" => "noul", "noul" => Float(noul) }
      end

      def choice_answer(stub, question)
        winner, confidence, probabilities = unpack_stub(stub, :choice) { stub.to_s }
        probabilities ||= default_choice_probabilities(question["criteria"] || {}, winner)
        {
          "type" => "choice",
          "choice" => winner.to_s,
          "confidence" => Float(confidence),
          "probabilities" => probabilities.to_h { |key, value| [key.to_s, Float(value)] }
        }
      end

      def default_choice_probabilities(criteria, winner)
        keys = criteria.keys.map(&:to_s)
        keys << winner unless keys.include?(winner)
        keys.to_h { |key| [key, key == winner ? 1.0 : 0.0] }
      end

      def score_answer(stub, question)
        score, confidence, probabilities = unpack_stub(stub, :score) { stub }
        probabilities ||= default_score_probabilities(question["criteria"] || [], score)
        {
          "type" => "score",
          "score" => Float(score),
          "confidence" => Float(confidence),
          "probabilities" => score_probability_hash(probabilities, question)
        }
      end

      def unpack_stub(stub, key)
        return [yield, 1.0, nil] unless stub_hash?(stub, key)

        [stub_field(stub, key), stub_field(stub, :confidence) || 1.0, stub_field(stub, :probabilities)]
      end

      def stub_hash?(stub, key)
        stub.is_a?(Hash) && (stub.key?(key) || stub.key?(key.to_s))
      end

      def stub_field(stub, key)
        stub[key] || stub[key.to_s]
      end

      def default_score_probabilities(criteria, score)
        size = [criteria.size, 1].max
        nearest = Float(score).round.clamp(0, size - 1)
        size.times.to_h { |index| [index.to_s, index == nearest ? 1.0 : 0.0] }
      end

      def score_probability_hash(probabilities, question)
        names = Jev.send(:level_names_for, question["instructions"])
        probabilities.to_h do |key, value|
          index = score_index(key, names)
          [index.to_s, Float(value)]
        end
      end

      def score_index(key, names)
        return key if key.is_a?(Integer)
        return Integer(key) if key.is_a?(String) && key.match?(/\A\d+\z/)

        names&.index(key.to_sym) || Integer(key)
      end
    end
  end
end
