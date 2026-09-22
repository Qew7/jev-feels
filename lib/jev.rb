# frozen_string_literal: true

require_relative "jev/version"
require_relative "jev/errors"
require_relative "jev/configuration"
require_relative "jev/definition"
require_relative "jev/registry"
require_relative "jev/result"
require_relative "jev/transport"
require_relative "jev/client"
require_relative "jev/query"
require_relative "jev/match"
require_relative "jev/harness"
require_relative "jev/feels"
require_relative "jev/model"

module Jev
  class << self
    attr_reader :configuration

    def configure
      yield configuration
      configuration
    end

    def reset_configuration!
      @configuration&.send(:close_transport)
      @configuration = Configuration.new
    end

    def define(scope_or_name, name_or_description, description = nil, **options)
      scope, name, instructions = unpack_define(scope_or_name, name_or_description, description)
      extras = adhoc_options(options)
      registry.define(scope, name, Definition.build(name: name, instructions: instructions, **extras))
    end

    def definition(scope_or_name, name = nil)
      found =
        if name.nil?
          registry.fetch(scope_or_name, scope: nil, fallback: false, inherit: false)
        else
          registry.fetch(name, scope: scope_or_name, fallback: false, inherit: false)
        end
      found&.public_value
    end

    def definitions(scope = nil)
      registry.all(scope)
    end

    def reset_definitions!
      registry.reset!
    end

    def feels(text, scope_or_predicate, predicate = nil)
      typed_measure(:noul, text, scope_or_predicate, predicate, id: Client::QUESTION_ID).probability
    end

    def feels?(text, scope_or_predicate, predicate = nil, **opts)
      validate_noul_decision!(opts)
      decide_noul(feels(text, scope_or_predicate, predicate), opts)
    end

    def decide(text, scope_or_predicate, predicate = nil, confidence: nil, **options)
      require_adhoc_type(scope_or_predicate, predicate, options, :choices)
      confidence = normalize_unit(confidence, "confidence") unless confidence.nil?
      result = typed_measure(:choice, text, scope_or_predicate, predicate, **options)
      return if confidence && result.confidence < confidence

      result.choice
    end

    def score(text, scope_or_predicate, predicate = nil, **options)
      require_adhoc_type(scope_or_predicate, predicate, options, :levels)
      typed_measure(:score, text, scope_or_predicate, predicate, **options).score
    end

    def measure(text, scope_or_predicate = nil, predicate = nil, **options, &block)
      if block
        raise ArgumentError, "unknown keyword: #{options.keys.first}" unless options.empty?
        raise ArgumentError, "predicate is not used with a measure block" unless predicate.nil?

        measure_batch(text, scope_or_predicate, &block)
      else
        raise ArgumentError, "question is required" if scope_or_predicate.nil?

        measure_one(text, scope_or_predicate, predicate, **options)
      end
    end

    def match(text, scope_or_predicate, predicate = nil, confidence: nil, **, &block)
      raise ArgumentError, "Jev.match requires a block" unless block

      matcher = Matcher.new(decide(text, scope_or_predicate, predicate, confidence: confidence, **))
      block.arity.zero? ? matcher.instance_eval(&block) : yield(matcher)
      matcher.result
    end

    def stub(answers, &)
      Harness.stub(answers, &)
    end

    def record(&)
      Harness.record(&)
    end

    def replay(tape, &)
      Harness.replay(tape, &)
    end

    def normalize_threshold(value)
      normalize_unit(value, "threshold")
    end

    def resolve_definition(predicate, scope: nil, **options)
      case predicate
      when Symbol
        raise ArgumentError, "unknown keyword: #{options.keys.first}" unless options.empty?

        registry.fetch(predicate, scope: scope) ||
          raise(UndefinedDefinition, undefined_message(predicate, scope))
      when String
        Definition.build(name: :adhoc, instructions: predicate, **adhoc_options(options))
      else
        raise ArgumentError, "predicate must be a Symbol or String"
      end
    end

    def name_for_instructions(instructions)
      registry.name_for_instructions(instructions)
    end

    def level_names_for(instructions)
      registry.find_by_instructions(instructions)&.level_names
    end
    private :resolve_definition, :name_for_instructions, :level_names_for

    private

    def normalize_unit(value, name)
      raise ArgumentError, "#{name} must be a Float between 0.0 and 1.0" unless value.is_a?(Numeric)

      value = Float(value)
      unless value.finite? && value.between?(0.0, 1.0)
        raise ArgumentError, "#{name} must be a Float between 0.0 and 1.0"
      end

      value
    end

    def require_adhoc_type(scope_or_predicate, predicate, options, key)
      _scope, name = unpack_predicate(scope_or_predicate, predicate)
      return unless name.is_a?(String)
      raise ArgumentError, "#{key} is required" unless options.key?(key)
    end

    attr_reader :registry

    def coerce_text(text)
      text = text.to_str if !text.is_a?(String) && text.respond_to?(:to_str)
      raise ArgumentError, "text must be a String" unless text.is_a?(String)

      text
    end

    def unpack_predicate(scope_or_predicate, predicate)
      return [nil, scope_or_predicate] if predicate.nil?
      raise ArgumentError, "scope must be a Module, String, or Symbol" unless scoped?(scope_or_predicate)

      [scope_or_predicate, predicate]
    end

    def scoped?(value)
      value.is_a?(Module) || value.is_a?(String) || value.is_a?(Symbol)
    end

    def undefined_message(predicate, scope)
      if scope
        "Undefined Jev definition: #{predicate.inspect} for #{scope}"
      else
        "Undefined Jev definition: #{predicate.inspect}"
      end
    end

    def unpack_define(scope_or_name, name_or_description, description)
      if description.nil?
        if scope_or_name.is_a?(Module) || name_or_description.is_a?(Symbol)
          raise ArgumentError, "description is required"
        end

        [nil, scope_or_name, name_or_description]
      else
        [scope_or_name, name_or_description, description]
      end
    end

    def adhoc_options(options)
      choices = options.delete(:choices)
      levels = options.delete(:levels)
      raise ArgumentError, "unknown keyword: #{options.keys.first}" unless options.empty?

      { choices: choices, levels: levels }
    end

    def measure_one(text, scope_or_predicate, predicate, id: nil, **)
      scope, predicate = unpack_predicate(scope_or_predicate, predicate)
      definition = resolve_definition(predicate, scope: scope, **)
      ask_definition(text, predicate, definition, id)
    end

    def typed_measure(type, text, scope_or_predicate, predicate, id: nil, **)
      scope, predicate = unpack_predicate(scope_or_predicate, predicate)
      definition = resolve_definition(predicate, scope: scope, **)
      unless definition.type == type
        raise ArgumentError, "#{predicate.inspect} is a #{definition.type} definition, not a #{type}"
      end

      ask_definition(text, predicate, definition, id)
    end

    def ask_definition(text, predicate, definition, id)
      question_id = id || (predicate.is_a?(Symbol) ? predicate.to_s : definition.type.to_s)
      Client.new(configuration).ask(coerce_text(text), { question_id => definition }).fetch(question_id)
    end

    def measure_batch(text, scope, &)
      questions = collect_questions(scope, &)
      answers = Client.new(configuration).ask(coerce_text(text), questions.transform_keys(&:to_s))
      Result::Batch.new(questions.keys.to_h { |key| [key, answers.fetch(key.to_s)] })
    end

    def collect_questions(scope)
      query = Query.new(scope)
      yield query
      raise ArgumentError, "measure block must declare at least one question" if query.questions.empty?

      query.questions
    end

    def validate_noul_decision!(opts)
      unknown = opts.keys - %i[threshold at_least]
      raise ArgumentError, "unknown keyword: #{unknown.first}" unless unknown.empty?
      if opts.key?(:at_least) && opts.key?(:threshold)
        raise ArgumentError,
              "cannot use threshold: and at_least: together"
      end

      normalize_unit(opts[:at_least], "at_least") if opts.key?(:at_least)
      normalize_threshold(opts[:threshold]) if opts.key?(:threshold)
    end

    def decide_noul(probability, opts)
      if opts.key?(:at_least)
        at_least = normalize_unit(opts[:at_least], "at_least")
        return true if probability >= at_least
        return false if probability + at_least <= 1.0

        nil
      else
        probability >= normalize_threshold(opts.fetch(:threshold, configuration.threshold))
      end
    end
  end

  private_constant :Query, :Matcher, :Harness

  reset_configuration!
  @registry = Registry.new
end
