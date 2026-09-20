# frozen_string_literal: true

RSpec.describe "Jev live API", :live do
  it "returns a noul from System One" do
    key = ENV["JEV_API_KEY"].to_s
    skip "set JEV_API_KEY to hit the real Jev API" if key.empty?

    Jev.configure { |config| config.api_key = key }
    Jev.define :urgent, "Requires immediate attention or action"

    noul = Jev.feels(
      "Our production server has stopped responding. Please investigate immediately.",
      :urgent
    )

    expect(noul).to be_a(Float)
    expect(noul).to be_between(0.0, 1.0)
  end
end
