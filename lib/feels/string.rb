# frozen_string_literal: true

require "feels"

class String
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
