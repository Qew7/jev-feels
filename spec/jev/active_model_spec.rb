# frozen_string_literal: true

require "feels/active_model"

RSpec.describe "ActiveModel integration" do
  before do
    Jev.define :appropriate, "This text is appropriate for publication"
    Jev.configure { |config| config.transport = FakeTransport.new(noul: 0.95) }
  end

  def model_class(**validation)
    Class.new do
      include ActiveModel::Model
      include Jev::ActiveModel

      attr_accessor :body

      validates_feeling :body, :appropriate, **validation
    end
  end

  it "accepts a passing predicate" do
    record = model_class(threshold: 0.9).new(body: "a polite review")

    expect(record).to be_valid
  end

  it "adds an error when the predicate fails" do
    Jev.configure { |config| config.transport = FakeTransport.new(noul: 0.2) }
    record = model_class(threshold: 0.9).new(body: "spam")

    expect(record).not_to be_valid
    expect(record.errors[:body]).to include("is not appropriate")
  end

  it "uses a custom message" do
    Jev.configure { |config| config.transport = FakeTransport.new(noul: 0.2) }
    record = model_class(threshold: 0.9, message: "is not publishable").new(body: "spam")

    record.valid?
    expect(record.errors[:body]).to eq(["is not publishable"])
  end

  it "does not call Jev when allow_nil skips the attribute" do
    transport = FakeTransport.new(noul: 0.9)
    Jev.configure { |config| config.transport = transport }
    record = model_class(allow_nil: true).new

    expect(record).to be_valid
    expect(transport.calls).to be_empty
  end

  it "does not call Jev when if: skips the validation" do
    transport = FakeTransport.new(noul: 0.9)
    Jev.configure { |config| config.transport = transport }
    record = model_class(if: -> { false }).new(body: "hello")

    expect(record).to be_valid
    expect(transport.calls).to be_empty
  end

  it "treats at_least nil as a validation failure" do
    Jev.configure { |config| config.transport = FakeTransport.new(noul: 0.5) }
    record = model_class(at_least: 0.8).new(body: "unclear")

    expect(record).not_to be_valid
  end

  it "adds validates_feeling via ActiveModel helpers" do
    klass = Class.new do
      include ActiveModel::Model

      attr_accessor :body

      validates_feeling :body, :appropriate, threshold: 0.9
    end

    expect(klass.new(body: "a polite review")).to be_valid
  end

  it "reads the current default threshold on every validation" do
    record = model_class.new(body: "hello")
    expect(record).to be_valid

    Jev.configuration.threshold = 0.99
    expect(record).not_to be_valid
  end

  it "still accepts the original options when validate is called directly" do
    record = model_class.new(body: "hello")
    Jev::ActiveModel.validate(record, :body, record.body, predicate: :appropriate, threshold: 0.99)

    expect(record.errors[:body]).to eq(["is not appropriate"])
  end

  it "validates against the class definition with inherited and global fallbacks" do
    parent = Class.new do
      include ActiveModel::Model
      include Jev::Model

      attr_accessor :body

      feels :body, :urgent, "parent urgent"
      validates_feeling :body, :urgent
    end
    child = Class.new(parent)
    Jev.define :urgent, "global urgent"
    transport = FakeTransport.new(noul: 0.9)
    Jev.configuration.transport = transport

    expect(child.new(body: "hello")).to be_valid
    expect(transport.calls.last.dig("questions", "feels", "instructions")).to eq("parent urgent")
    Jev.define child, :urgent, "child urgent"
    expect(child.new(body: "hello")).to be_valid
    expect(transport.calls.last.dig("questions", "feels", "instructions")).to eq("child urgent")
    Jev.reset_definitions!
    Jev.define :urgent, "global urgent"
    expect(child.new(body: "hello")).to be_valid
    expect(transport.calls.last.dig("questions", "feels", "instructions")).to eq("global urgent")
  end
end
