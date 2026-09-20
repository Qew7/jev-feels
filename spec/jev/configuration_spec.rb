# frozen_string_literal: true

RSpec.describe Jev::Configuration do
  it "exposes documented defaults" do
    expect(Jev.configuration.api_key).to be_nil
    expect(Jev.configuration.base_url).to eq("https://api.typesafe.ai")
    expect(Jev.configuration.timeout).to eq(10.0)
    expect(Jev.configuration.threshold).to eq(0.5)
    expect(Jev.configuration.transport).to be_nil
  end

  it "yields the live configuration" do
    Jev.configure do |config|
      config.api_key = "sk-test"
      config.base_url = "https://example.test"
      config.timeout = 3
      config.threshold = 0.8
    end

    expect(Jev.configuration.api_key).to eq("sk-test")
    expect(Jev.configuration.base_url).to eq("https://example.test")
    expect(Jev.configuration.timeout).to eq(3.0)
    expect(Jev.configuration.threshold).to eq(0.8)
  end

  it "resets configuration" do
    Jev.configure { |config| config.api_key = "sk-test" }
    Jev.reset_configuration!

    expect(Jev.configuration.api_key).to be_nil
    expect(Jev.configuration.threshold).to eq(0.5)
  end

  it "rejects an invalid threshold on configure" do
    expect { Jev.configure { |config| config.threshold = 2 } }.to raise_error(ArgumentError)
  end

  it "raises when the API key is missing and the default transport is used" do
    Jev.define :urgent, "Requires immediate attention or action"

    expect { Jev.feels("hello", :urgent) }.to raise_error(
      Jev::ConfigurationError,
      "Jev API key is missing"
    )
  end
end
