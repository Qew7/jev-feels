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
      @mutex.synchronize do
        (@definitions[scope] ||= {})[key] = value
      end
      value
    end

    def fetch(name, scope: nil, fallback: true)
      key = name.to_sym
      @mutex.synchronize do
        scoped = @definitions.dig(scope, key) if scope
        return scoped if scoped
        return unless fallback || scope.nil?

        @definitions.dig(nil, key)
      end
    end

    def all(scope = nil)
      @mutex.synchronize { (@definitions[scope] || {}).dup.freeze }
    end

    def reset!
      @mutex.synchronize { @definitions.clear }
    end
  end
end
