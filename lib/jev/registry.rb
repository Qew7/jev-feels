# frozen_string_literal: true

module Jev
  class Registry
    def initialize
      @mutex = Mutex.new
      @definitions = {}
    end

    def define(scope, name, description)
      key = name.to_sym
      value = description.to_s.dup.freeze
      scope_key = storage_key(scope)
      @mutex.synchronize do
        (@definitions[scope_key] ||= {})[key] = value
      end
      value
    end

    def fetch(name, scope: nil, fallback: true, inherit: true)
      key = name.to_sym
      @mutex.synchronize do
        return @definitions.dig(nil, key) if scope.nil?

        lookup_keys(scope, inherit: inherit).each do |scope_key|
          found = @definitions.dig(scope_key, key)
          return found if found
        end
        return @definitions.dig(nil, key) if fallback

        nil
      end
    end

    def all(scope = nil)
      @mutex.synchronize { (@definitions[storage_key(scope)] || {}).dup.freeze }
    end

    def reset!
      @mutex.synchronize { @definitions.clear }
    end

    private

    def storage_key(scope)
      return if scope.nil?

      key =
        case scope
        when String, Symbol then scope.to_s
        when Module then scope.name || scope
        else raise ArgumentError, "scope must be a Module, String, or Symbol"
        end
      raise ArgumentError, "scope must be a non-empty String" if key.is_a?(String) && key.empty?

      key
    end

    def lookup_keys(scope, inherit:)
      keys = [storage_key(scope)]
      return keys unless inherit

      klass = scope.is_a?(Class) ? scope : constantize(scope)
      return keys unless klass.is_a?(Class)

      current = klass.superclass
      while current && current != Object
        keys << (current.name || current)
        current = current.superclass
      end
      keys.uniq
    end

    def constantize(name)
      name = name.to_s if name.is_a?(Symbol)
      return unless name.is_a?(String)

      name.split("::").reduce(Object) { |mod, part| mod.const_get(part, false) }
    rescue NameError
      nil
    end
  end
end
