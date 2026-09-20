# frozen_string_literal: true

RSpec.describe Jev::Model do
  def model_class(parent: Object, &block)
    Class.new(parent) do
      include Jev::Model unless parent < Jev::Model
      attr_accessor :body, :subject

      class_eval(&block) if block
    end
  end

  def record(klass, **attrs)
    klass.new.tap { |row| attrs.each { |key, value| row.public_send("#{key}=", value) } }
  end

  before do
    Jev.configure { |config| config.transport = FakeTransport.new(noul: 0.94) }
  end

  it "reads the declared field and uses the enclosing class as scope" do
    klass = model_class { feels :body, :urgent, "Outage, customers cannot sign in" }
    transport = FakeTransport.new(noul: 0.94)
    Jev.configure { |config| config.transport = transport }

    expect(record(klass, body: "the site is down").feels?(:urgent)).to be true
    expect(transport.calls.last.dig("questions", "feels", "instructions"))
      .to eq("Outage, customers cannot sign in")
    expect(Jev.definition(klass, :urgent)).to eq("Outage, customers cannot sign in")
  end

  it "returns the probability from feels" do
    klass = model_class { feels :body, :urgent, "Outage, customers cannot sign in" }

    expect(record(klass, body: "the site is down").feels(:urgent)).to eq(0.94)
  end

  it "forwards a custom threshold" do
    klass = model_class { feels :body, :urgent, "Outage, customers cannot sign in" }

    expect(record(klass, body: "the site is down").feels?(:urgent, threshold: 0.95)).to be false
  end

  it "treats a nil field as an empty string" do
    klass = model_class { feels :body, :urgent, "Outage, customers cannot sign in" }
    transport = FakeTransport.new(noul: 0.1)
    Jev.configure { |config| config.transport = transport }

    expect(record(klass).feels?(:urgent)).to be false
    expect(transport.calls.last["state"]).to eq("")
  end

  it "uses a different field per predicate" do
    klass = model_class do
      feels :body, :urgent, "Outage"
      feels :subject, :spam, "Unsolicited"
    end
    transport = FakeTransport.new(noul: 0.94)
    Jev.configure { |config| config.transport = transport }

    row = record(klass, body: "server down", subject: "Cheap meds")
    row.feels?(:spam)
    expect(transport.calls.last["state"]).to eq("Cheap meds")
  end

  it "inherits the parent field mapping on a subclass" do
    parent = model_class { feels :body, :urgent, "Legal takedown request" }
    child = model_class(parent: parent)
    transport = FakeTransport.new(noul: 0.94)
    Jev.configure { |config| config.transport = transport }

    expect(record(child, body: "take this down").feels?(:urgent)).to be true
    expect(transport.calls.last.dig("questions", "feels", "instructions"))
      .to eq("Legal takedown request")
  end

  it "lets a subclass override the parent definition" do
    parent = model_class { feels :body, :urgent, "parent" }
    child = model_class(parent: parent) { feels :body, :urgent, "child" }
    transport = FakeTransport.new(noul: 0.94)
    Jev.configure { |config| config.transport = transport }

    record(child, body: "take this down").feels?(:urgent)
    expect(transport.calls.last.dig("questions", "feels", "instructions")).to eq("child")
  end

  it "raises when the predicate was never bound to a field" do
    klass = model_class

    expect { record(klass, body: "x").feels?(:urgent) }.to raise_error(
      Jev::UndefinedDefinition,
      "Undefined Jev definition: :urgent for #{klass}"
    )
  end
end
