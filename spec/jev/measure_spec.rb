# frozen_string_literal: true

RSpec.describe "Jev.measure" do
  before do
    Jev.define :urgent, "Requires immediate attention or action"
    Jev.define :angry, "Expresses anger or hostility"
    Jev.define :support_team, "Which team?", choices: { billing: "refunds", technical: "bugs" }
    Jev.define :severity, "How severe?", levels: {
      cosmetic: "visual",
      degraded: "workaround",
      blocking: "stuck",
      critical: "outage"
    }
  end

  def batch_transport
    transport = ScriptedTransport.new do |_payload|
      {
        "answers" => {
          "urgent" => { "type" => "noul", "noul" => 0.91 },
          "angry" => { "type" => "noul", "noul" => 0.12 },
          "support_team" => {
            "type" => "choice",
            "choice" => "billing",
            "confidence" => 0.88,
            "probabilities" => { "billing" => 0.88, "technical" => 0.12 }
          },
          "severity" => {
            "type" => "score",
            "score" => 2.37,
            "confidence" => 0.7,
            "probabilities" => { "0" => 0.0, "1" => 0.1, "2" => 0.7, "3" => 0.2 }
          }
        }
      }
    end
    Jev.configure { |config| config.transport = transport }
    transport
  end

  it "returns a Noul result" do
    Jev.configure do |config|
      config.transport = lambda { |_payload|
        { "answers" => { "urgent" => { "type" => "noul", "noul" => 0.93 } } }
      }
    end

    result = Jev.measure("the site is down", :urgent)
    expect(result).to be_a(Jev::Result::Noul)
    expect(result.probability).to eq(0.93)
    expect(result.type).to eq(:noul)
  end

  it "sends every batch question in one request" do
    transport = batch_transport

    result = Jev.measure("charged twice and cannot pay") do |q|
      q.feels :urgent
      q.feels :angry
      q.decide :support_team
      q.score :severity
    end

    expect(transport.calls.size).to eq(1)
    expect(transport.calls.first["state"]).to eq("charged twice and cannot pay")
    expect(transport.calls.first["questions"].keys).to contain_exactly(
      "urgent", "angry", "support_team", "severity"
    )
    expect(result).to be_a(Jev::Result::Batch)
    expect(result[:urgent]).to be_a(Jev::Result::Noul)
    expect(result[:support_team]).to be_a(Jev::Result::Choice)
    expect(result[:severity]).to be_a(Jev::Result::Score)
    expect(result.to_h).to eq(
      urgent: true,
      angry: false,
      support_team: :billing,
      severity: 2.37
    )
  end

  it "rejects an ad-hoc string in a batch" do
    expect do
      Jev.measure("hello") { |q| q.feels "sounds angry" }
    end.to raise_error(ArgumentError, "batch questions must be a defined Symbol")
  end

  it "uses collapsed values for pattern matching without another request" do
    transport = batch_transport
    result = Jev.measure("charged twice") do |q|
      q.feels :urgent
      q.decide :support_team
      q.score :severity
    end

    routed =
      case result
      in { urgent: true, support_team: :billing }
        :billing
      in { support_team: :technical }
        :technical
      else
        :manual
      end

    expect(routed).to eq(:billing)
    expect(transport.calls.size).to eq(1)
  end

  it "matches a Score with a Ruby range" do
    batch_transport
    result = Jev.measure("cannot checkout") do |q|
      q.feels :urgent
      q.score :severity
    end

    matched =
      case result
      in { urgent: true, severity: 2.0.. }
        :escalate
      else
        :hold
      end

    expect(matched).to eq(:escalate)
  end
end
