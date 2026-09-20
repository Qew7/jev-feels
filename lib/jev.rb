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

    def define(name, description)
      registry.define(name, description)
    end

    def definition(name)
      registry.fetch(name)
    end

    def definitions
      registry.all
    end

    def reset_definitions!
      registry.reset!
    end

    def feels(text, predicate)
      Client.new(configuration).probability(coerce_text(text), resolve(predicate))
    end

    def feels?(text, predicate, threshold: configuration.threshold)
      feels(text, predicate) >= normalize_threshold(threshold)
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

    def resolve(predicate)
      case predicate
      when Symbol
        definition(predicate) ||
          raise(UndefinedDefinition, "Undefined Jev definition: #{predicate.inspect}")
      when String
        predicate
      else
        raise ArgumentError, "predicate must be a Symbol or String"
      end
    end
  end

  reset_configuration!
  @registry = Registry.new
end
