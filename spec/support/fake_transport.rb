# frozen_string_literal: true

class FakeTransport
  attr_reader :calls

  def initialize(noul: 0.94, error: nil, response: nil)
    @noul = noul
    @error = error
    @response = response
    @calls = []
  end

  def call(payload)
    @calls << payload
    raise @error if @error
    return @response unless @response.nil?

    { "answers" => { "feels" => { "type" => "noul", "noul" => @noul } } }
  end
end
