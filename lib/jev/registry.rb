# frozen_string_literal: true

module Jev
  class Registry
    def initialize
      @mutex = Mutex.new
      @definitions = {}
    end

    def define(name, description)
      key = name.to_sym
      value = description.to_s.dup.freeze
      @mutex.synchronize { @definitions[key] = value }
      value
    end

    def fetch(name)
      @mutex.synchronize { @definitions[name.to_sym] }
    end

    def all
      @mutex.synchronize { @definitions.dup.freeze }
    end

    def reset!
      @mutex.synchronize { @definitions.clear }
    end
  end
end
