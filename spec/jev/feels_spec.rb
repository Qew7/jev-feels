# frozen_string_literal: true

RSpec.describe "Jev.feels / Jev.feels?" do
  def stub_noul(noul)
    FakeTransport.new(noul: noul).tap do |transport|
      Jev.configure { |config| config.transport = transport }
    end
  end

  before do
    Jev.define :urgent, "Requires immediate attention or action"
  end

  it "returns the noul probability" do
    stub_noul(0.94)

    expect(Jev.feels("Production database is down. Please respond immediately.", :urgent)).to eq(0.94)
  end

  it "is true when the probability meets the default threshold" do
    stub_noul(0.5)

    expect(Jev.feels?("Production database is down. Please respond immediately.", :urgent)).to be true
  end

  it "is false when the probability is below the default threshold" do
    stub_noul(0.49)

    expect(Jev.feels?("Hope you are well.", :urgent)).to be false
  end

  it "accepts a custom threshold" do
    stub_noul(0.79)

    expect(Jev.feels?("Please respond immediately.", :urgent, threshold: 0.8)).to be false
    expect(Jev.feels?("Please respond immediately.", :urgent, threshold: 0.79)).to be true
  end

  it "uses the configured default threshold" do
    stub_noul(0.7)
    Jev.configure { |config| config.threshold = 0.8 }

    expect(Jev.feels?("Please respond immediately.", :urgent)).to be false
  end

  it "rejects an invalid threshold" do
    stub_noul(0.9)

    expect { Jev.feels?("x", :urgent, threshold: -0.1) }.to raise_error(
      ArgumentError, "threshold must be a Float between 0.0 and 1.0"
    )
    expect { Jev.feels?("x", :urgent, threshold: 1.1) }.to raise_error(ArgumentError)
    expect { Jev.feels?("x", :urgent, threshold: "0.5") }.to raise_error(ArgumentError)
  end

  it "raises for an undefined symbol" do
    expect do
      Jev.feels?("hello", :something_that_was_never_defined)
    end.to raise_error(
      Jev::UndefinedDefinition,
      "Undefined Jev definition: :something_that_was_never_defined"
    )
  end

  it "does not turn an undefined symbol into a humanized string" do
    transport = stub_noul(0.9)

    expect { Jev.feels("hello", :nope) }.to raise_error(Jev::UndefinedDefinition)
    expect(transport.calls).to be_empty
  end

  it "evaluates an ad-hoc string predicate without registering it" do
    transport = stub_noul(0.88)

    expect(
      Jev.feels?("Need this by tomorrow.", "requires a response within 24 hours")
    ).to be true
    expect(Jev.definitions).to eq(urgent: "Requires immediate attention or action")
    expect(transport.calls.first.dig("questions", "feels", "instructions"))
      .to eq("requires a response within 24 hours")
  end

  it "sends registered instructions as a Noul question" do
    transport = stub_noul(0.91)

    Jev.feels("the server is down", :urgent)

    expect(transport.calls.first).to eq(
      "model" => "jev-latest",
      "state" => "the server is down",
      "questions" => {
        "feels" => {
          "type" => "noul",
          "instructions" => "Requires immediate attention or action"
        }
      }
    )
  end

  it "uses an injected transport" do
    transport = FakeTransport.new(noul: 0.42)
    Jev.configure { |config| config.transport = transport }

    expect(Jev.feels("x", :urgent)).to eq(0.42)
    expect(transport.calls.size).to eq(1)
  end

  it "raises when the transport returns a malformed body" do
    Jev.configure { |config| config.transport = FakeTransport.new(response: {}) }

    expect { Jev.feels("x", :urgent) }.to raise_error(Jev::InvalidResponseError, /missing answers/)
  end

  it "normalizes noul values into 0.0..1.0" do
    stub_noul(1.2)

    expect(Jev.feels("x", :urgent)).to eq(1.0)
  end

  it "does not monkey-patch String on require 'feels'" do
    lib = File.expand_path("../../lib", __dir__)
    output = IO.popen(
      { "RUBYOPT" => nil },
      ["ruby", "-I", lib, "-rfeels", "-e", "print String.instance_methods(false).include?(:feels)"],
      &:read
    )

    expect($CHILD_STATUS).to be_success
    expect(output).to eq("false")
  end

  it "loads the same API via require 'jev-feels'" do
    lib = File.expand_path("../../lib", __dir__)
    output = IO.popen(
      { "RUBYOPT" => nil },
      ["ruby", "-I", lib, "-rjev-feels", "-e", "print defined?(Jev)"],
      &:read
    )

    expect($CHILD_STATUS).to be_success
    expect(output).to eq("constant")
  end

  it "uses a model-scoped definition when the same name exists twice" do
    email = Class.new
    comment = Class.new
    Jev.define email, :urgent, "Outage, customers cannot sign in"
    Jev.define comment, :urgent, "Legal takedown request"
    transport = stub_noul(0.9)

    Jev.feels("the site is down", email, :urgent)

    expect(transport.calls.last.dig("questions", "feels", "instructions"))
      .to eq("Outage, customers cannot sign in")
  end

  it "falls back to a global definition when the model has no override" do
    email = Class.new
    transport = stub_noul(0.9)

    Jev.feels("the site is down", email, :urgent)

    expect(transport.calls.last.dig("questions", "feels", "instructions"))
      .to eq("Requires immediate attention or action")
  end

  it "raises when a scoped name is missing and there is no global" do
    email = Class.new

    expect { Jev.feels?("hello", email, :missing) }.to raise_error(
      Jev::UndefinedDefinition,
      "Undefined Jev definition: :missing for #{email}"
    )
  end
end
