# frozen_string_literal: true

require_relative "jev/version"
require_relative "jev/errors"
require_relative "jev/configuration"
require_relative "jev/registry"
require_relative "jev/transport"
require_relative "jev/client"
require_relative "jev/feels"

module Jev
  class << self
    attr_reader :configuration

    def configure
      yield configuration
      configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    def define(scope_or_name, name_or_description, description = nil)
      if scope_or_name.is_a?(Module)
        raise ArgumentError, "description is required" if description.nil?

        registry.define(scope_or_name, name_or_description, description)
      else
        raise ArgumentError, "wrong number of arguments (given 3, expected 2)" unless description.nil?

        registry.define(nil, scope_or_name, name_or_description)
      end
    end

    def definition(scope_or_name, name = nil)
      if name.nil?
        registry.fetch(scope_or_name, scope: nil, fallback: false)
      else
        raise ArgumentError, "scope must be a Module" unless scope_or_name.is_a?(Module)

        registry.fetch(name, scope: scope_or_name, fallback: false)
      end
    end

    def definitions(scope = nil)
      raise ArgumentError, "scope must be a Module" unless scope.nil? || scope.is_a?(Module)

      registry.all(scope)
    end

    def reset_definitions!
      registry.reset!
    end

    def feels(text, scope_or_predicate, predicate = nil)
      scope, predicate = unpack_predicate(scope_or_predicate, predicate)
      Client.new(configuration).probability(coerce_text(text), resolve(predicate, scope: scope))
    end

    def feels?(text, scope_or_predicate, predicate = nil, threshold: configuration.threshold)
      feels(text, scope_or_predicate, predicate) >= normalize_threshold(threshold)
    end

    def normalize_threshold(value)
      raise ArgumentError, "threshold must be a Float between 0.0 and 1.0" unless value.is_a?(Numeric)

      value = Float(value)
      unless value.finite? && value.between?(0.0, 1.0)
        raise ArgumentError, "threshold must be a Float between 0.0 and 1.0"
      end

      value
    end

    private

    attr_reader :registry

    def coerce_text(text)
      text = text.to_str if !text.is_a?(String) && text.respond_to?(:to_str)
      raise ArgumentError, "text must be a String" unless text.is_a?(String)

      text
    end

    def unpack_predicate(scope_or_predicate, predicate)
      return [nil, scope_or_predicate] if predicate.nil?
      raise ArgumentError, "scope must be a Module" unless scope_or_predicate.is_a?(Module)

      [scope_or_predicate, predicate]
    end

    def resolve(predicate, scope: nil)
      case predicate
      when Symbol
        registry.fetch(predicate, scope: scope) ||
          raise(UndefinedDefinition, undefined_message(predicate, scope))
      when String
        predicate
      else
        raise ArgumentError, "predicate must be a Symbol or String"
      end
    end

    def undefined_message(predicate, scope)
      if scope
        "Undefined Jev definition: #{predicate.inspect} for #{scope}"
      else
        "Undefined Jev definition: #{predicate.inspect}"
      end
    end
  end

  reset_configuration!
  @registry = Registry.new
end
