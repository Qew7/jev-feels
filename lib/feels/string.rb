# frozen_string_literal: true

require "feels"

class String
  def feels(...)
    Jev.feels(self, ...)
  end

  def feels?(...)
    Jev.feels?(self, ...)
  end
end
