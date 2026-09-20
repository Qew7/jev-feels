# frozen_string_literal: true

module Jev
  module Feels
    refine String do
      def feels(...)
        Jev.feels(self, ...)
      end

      def feels?(...)
        Jev.feels?(self, ...)
      end

      def decide(...)
        Jev.decide(self, ...)
      end

      def score(...)
        Jev.score(self, ...)
      end

      def measure(...)
        Jev.measure(self, ...)
      end
    end
  end
end
