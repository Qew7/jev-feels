# frozen_string_literal: true

require "json"

module Jev
  module Harness
    THREAD_KEY = :jev_transport

    module_function

    def current_transport(configuration)
      Thread.current[THREAD_KEY] || configuration.transport || configuration.send(:default_transport)
    end

    def dispatch(transport, payload, definitions)
      if transport.is_a?(StubTransport) || transport.is_a?(RecordingTransport)
        transport.call(payload, definitions)
      else
        transport.call(payload)
      end
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
        @entries = []
        @index = {}
        entries.each { |entry| record(entry.fetch("request"), entry.fetch("response")) }
      end

      def record(payload, response)
        request = canonical(payload)
        entry = { "request" => request, "response" => canonical(response) }.freeze
        @entries << entry
        @index[request] ||= entry
      end

      def lookup(payload)
        request = canonical(payload, sort: false)
        entry = @index[request]
        raise ReplayError, replay_message(payload) unless entry

        copy(entry["response"])
      end

      def to_json(*)
        JSON.generate({ "version" => 1, "entries" => @entries })
      end

      def self.parse(json)
        payload = json.is_a?(String) ? JSON.parse(json) : json
        raise ArgumentError, "tape is not a JSON object" unless payload.is_a?(Hash)

        entries = payload["entries"]
        raise ArgumentError, "tape is missing entries" unless entries.is_a?(Array)

        raise ArgumentError, "tape contains an invalid entry" unless entries.all? { |entry| valid_entry?(entry) }

        new(entries)
      end

      def self.valid_entry?(entry)
        entry.is_a?(Hash) && entry["request"].is_a?(Hash) && entry["response"].is_a?(Hash)
      end
      private_class_method :valid_entry?

      private

      def canonical(value, sort: true)
        case value
        when Hash
          canonical_hash(value, sort: sort)
        when Array
          value.map { |item| canonical(item, sort: sort) }.freeze
        when String
          value.dup.freeze
        else
          value
        end
      end

      def canonical_hash(value, sort:)
        pairs = value.transform_keys(&:to_s)
        pairs = pairs.sort.to_h if sort
        pairs.transform_values { |item| canonical(item, sort: sort) }.freeze
      end

      def copy(value)
        case value
        when Hash then value.transform_values { |item| copy(item) }
        when Array then value.map { |item| copy(item) }
        when String then value.dup
        else value
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

      def call(payload, definitions = {})
        response = Harness.dispatch(@inner, payload, definitions)
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

      def call(payload, definitions = {})
        questions = payload.fetch("questions")
        {
          "answers" => questions.to_h { |id, question| [id, answer_for(id, question, definitions[id])] }
        }
      end

      private

      def answer_for(id, question, definition)
        stub = find_stub(id, definition)
        raise ArgumentError, "unstubbed Jev question: #{id}" if stub.nil?

        case question["type"]
        when "noul" then noul_answer(stub)
        when "choice" then choice_answer(stub, question)
        when "score" then score_answer(stub, question, definition)
        else
          raise ArgumentError, "unstubbed Jev question: #{id}"
        end
      end

      def find_stub(id, definition)
        name = definition&.name || id.to_sym
        @answers.key?(name) ? @answers[name] : @answers[id.to_sym]
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

      def score_answer(stub, question, definition)
        score, confidence, probabilities = unpack_stub(stub, :score) { stub }
        probabilities ||= default_score_probabilities(question["criteria"] || [], score)
        {
          "type" => "score",
          "score" => Float(score),
          "confidence" => Float(confidence),
          "probabilities" => score_probability_hash(probabilities, definition)
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
        score = Float(score)
        maximum = criteria.size - 1
        unless score.finite? && score.between?(0, maximum)
          raise ArgumentError, "stub score must be between 0 and #{maximum}"
        end

        criteria.size.times.to_h { |index| [index.to_s, [1.0 - (index - score).abs, 0.0].max] }
      end

      def score_probability_hash(probabilities, definition)
        names = definition&.level_names
        indexes = nil
        probabilities.to_h do |key, value|
          index = score_index(key) { indexes ||= names&.each_with_index&.to_h }
          [index.to_s, Float(value)]
        end
      end

      def score_index(key)
        return key if key.is_a?(Integer)
        return Integer(key) if key.is_a?(String) && key.match?(/\A\d+\z/)

        yield&.[](key.to_sym) || Integer(key)
      end
    end
  end
end
