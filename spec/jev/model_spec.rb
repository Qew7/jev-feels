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

  it "binds feels to a field when the definition already exists" do
    Jev.define :urgent, "Requires immediate attention or action"
    klass = model_class { feels :body, :urgent }

    expect(record(klass, body: "the site is down").feels?(:urgent)).to be true
  end

  it "decides a Choice from the bound field" do
    Jev.define :support_team, "Which team?", choices: { billing: "refunds", technical: "bugs" }
    klass = model_class { decide :body, :support_team }
    Jev.configure do |config|
      config.transport = lambda { |_payload|
        {
          "answers" => {
            "support_team" => {
              "type" => "choice",
              "choice" => "billing",
              "confidence" => 1.0,
              "probabilities" => { "billing" => 1.0, "technical" => 0.0 }
            }
          }
        }
      }
    end

    expect(record(klass, body: "I was charged twice").decide(:support_team)).to eq(:billing)
  end

  it "defines a scoped Choice when decide is given a description" do
    klass = model_class do
      decide :body, :support_team, "Which team?", choices: { billing: "refunds", technical: "bugs" }
    end
    transport = ScriptedTransport.new do |_payload|
      {
        "answers" => {
          "support_team" => {
            "type" => "choice",
            "choice" => "technical",
            "confidence" => 1.0,
            "probabilities" => { "billing" => 0.0, "technical" => 1.0 }
          }
        }
      }
    end
    Jev.configure { |config| config.transport = transport }

    expect(record(klass, body: "the API is down").decide(:support_team)).to eq(:technical)
    expect(transport.calls.last.dig("questions", "support_team", "instructions")).to eq("Which team?")
  end

  def choice_score_answers
    {
      "answers" => {
        "support_team" => {
          "type" => "choice",
          "choice" => "billing",
          "confidence" => 0.9,
          "probabilities" => { "billing" => 0.9, "technical" => 0.1 }
        },
        "severity" => {
          "type" => "score",
          "score" => 2.1,
          "confidence" => 0.8,
          "probabilities" => { "0" => 0.1, "1" => 0.2, "2" => 0.7 }
        },
        "urgent" => { "type" => "noul", "noul" => 0.94 }
      }
    }
  end

  it "scores, measures, and matches from the bound field" do
    Jev.define :support_team, "Which team?", choices: { billing: "refunds", technical: "bugs" }
    Jev.define :severity, "How severe?", levels: { low: "nudge", mid: "hurt", high: "down" }
    klass = model_class do
      feels :body, :urgent, "Outage"
      decide :body, :support_team
      score :body, :severity
    end
    transport = ScriptedTransport.new { |_payload| choice_score_answers }
    Jev.configure { |config| config.transport = transport }
    email = record(klass, body: "charged twice")

    expect(email.score(:severity)).to eq(2.1)
    expect(email.measure(:urgent).probability).to eq(0.94)
    expect(email.match(:support_team) { on(:billing) { :ok } }).to eq(:ok)

    batch = email.measure do |q|
      q.feels :urgent
      q.decide :support_team
      q.score :severity
    end
    expect(batch.to_h).to eq(urgent: true, support_team: :billing, severity: 2.1)
    expect(transport.calls.last["state"]).to eq("charged twice")
  end
end
