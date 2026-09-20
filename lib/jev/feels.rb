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
    end
  end
end
