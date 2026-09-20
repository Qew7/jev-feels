# frozen_string_literal: true

module Jev
  class Matcher
    def initialize(choice)
      @choice = choice
      @handled = false
      @result = nil
    end

    def on(*keys)
      return @result if @handled
      return unless keys.map(&:to_sym).include?(@choice)

      @handled = true
      @result = yield
    end

    def otherwise
      return @result if @handled

      @handled = true
      @result = yield
    end

    attr_reader :result
  end
end
