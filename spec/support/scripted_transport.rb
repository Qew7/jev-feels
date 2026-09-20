# frozen_string_literal: true

class ScriptedTransport
  attr_reader :calls

  def initialize(&block)
    @block = block
    @calls = []
  end

  def call(payload)
    @calls << payload
    @block.call(payload)
  end
end
