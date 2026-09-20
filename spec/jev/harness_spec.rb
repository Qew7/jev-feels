# frozen_string_literal: true

RSpec.describe "Jev.stub / record / replay" do
  let(:endpoint) { "https://api.typesafe.ai/v1/systemone" }

  before do
    Jev.define :urgent, "Requires immediate attention or action"
    Jev.define :support_team, "Which team?", choices: { billing: "refunds", technical: "bugs" }
    Jev.define :severity, "How severe?", levels: { cosmetic: "visual", blocking: "stuck" }
  end

  it "stubs named answers without a network call" do
    Jev.configure { |config| config.api_key = "sk-test-secret-key" }

    Jev.stub(urgent: 0.95, support_team: :billing, severity: 2.4) do
      expect(Jev.feels?("the site is down", :urgent)).to be true
      expect(Jev.decide("charged twice", :support_team)).to eq(:billing)
      expect(Jev.score("cannot pay", :severity)).to eq(2.4)
    end

    expect(WebMock).not_to have_requested(:post, endpoint)
  end

  it "accepts a full Choice and Score result" do
    Jev.stub(
      support_team: {
        choice: :technical,
        confidence: 0.42,
        probabilities: { billing: 0.4, technical: 0.6 }
      },
      severity: {
        score: 1.1,
        confidence: 0.3,
        probabilities: { cosmetic: 0.2, blocking: 0.8 }
      }
    ) do
      result = Jev.measure("outage") do |q|
        q.decide :support_team
        q.score :severity
      end

      expect(result[:support_team].choice).to eq(:technical)
      expect(result[:support_team].confidence).to eq(0.42)
      expect(result[:severity].score).to eq(1.1)
      expect(result[:severity].probabilities[:blocking]).to eq(0.8)
    end
  end

  it "restores the previous transport after the stub block" do
    Jev.configure { |config| config.transport = FakeTransport.new(noul: 0.1) }

    Jev.stub(urgent: 0.99) do
      expect(Jev.feels("x", :urgent)).to eq(0.99)
    end

    expect(Jev.feels("x", :urgent)).to eq(0.1)
  end

  it "keeps stub state on the current thread" do
    seen = Queue.new
    Jev.configure { |config| config.transport = FakeTransport.new(noul: 0.11) }

    thread = Thread.new do
      seen << Jev.feels("x", :urgent)
    end

    Jev.stub(urgent: 0.99) do
      expect(Jev.feels("x", :urgent)).to eq(0.99)
      thread.join
    end

    expect(seen.pop).to eq(0.11)
  end

  it "records and replays the same request without the network" do
    inner = FakeTransport.new(noul: 0.77)
    Jev.configure { |config| config.transport = inner }

    tape = Jev.record do
      expect(Jev.feels("the site is down", :urgent)).to eq(0.77)
    end

    json = tape.to_json
    expect(json).to include("the site is down")
    expect(json).not_to include("Authorization")
    expect(json).not_to include("sk-")
    expect(JSON.parse(json)).to eq(JSON.parse(tape.to_json))

    Jev.configure { |config| config.transport = ->(_payload) { raise "network" } }

    Jev.replay(json) do
      expect(Jev.feels("the site is down", :urgent)).to eq(0.77)
    end
  end

  it "does not replay a different question from the tape" do
    Jev.configure { |config| config.transport = FakeTransport.new(noul: 0.77) }
    tape = Jev.record { Jev.feels("the site is down", :urgent) }

    Jev.replay(tape) do
      expect { Jev.feels("a different state", :urgent) }.to raise_error(Jev::ReplayError)
    end
  end

  it "does not store API keys when recording the real transport" do
    Jev.reset_configuration!
    Jev.configure { |config| config.api_key = "sk-test-secret-key" }
    stub_request(:post, endpoint).to_return(
      status: 200,
      body: JSON.generate("answers" => { "feels" => { "type" => "noul", "noul" => 0.5 } }),
      headers: { "Content-Type" => "application/json" }
    )

    tape = Jev.record { Jev.feels("hello", :urgent) }

    expect(tape.to_json).not_to include("sk-test-secret-key")
    expect(tape.to_json).not_to include("Authorization")
  end
end
