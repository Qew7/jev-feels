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

  it "distinguishes names with identical instructions for single and batch stubs" do
    Jev.define :first, "same instructions"
    Jev.define :second, "same instructions"

    Jev.stub(first: 0.1, second: 0.9) do
      expect(Jev.feels("hello", :second)).to eq(0.9)
      expect(Jev.feels("hello", :first)).to eq(0.1)
      expect(Jev.measure("hello") { |q| q.feels :second }.to_h).to eq(second: true)
    end
  end

  it "uses the actual scoped Score level names when instructions collide" do
    scope = Class.new
    Jev.define :other, "same instructions", levels: { low: "low", high: "high" }
    Jev.define scope, :severity, "same instructions", levels: { small: "small", large: "large" }

    Jev.stub(severity: { score: 0.8, probabilities: { small: 0.2, large: 0.8 } }) do
      result = Jev.measure("hello", scope, :severity)
      expect(result.probabilities).to eq(small: 0.2, large: 0.8)
    end
  end

  it "supports named level probabilities for an ad-hoc Score stub" do
    Jev.stub(score: { score: 0.8, probabilities: { low: 0.2, high: 0.8 } }) do
      result = Jev.measure("hello", "severity", levels: { low: "low", high: "high" })
      expect(result.probabilities).to eq(low: 0.2, high: 0.8)
    end
  end

  it "preserves definition identity through nested recording transports" do
    Jev.define :first, "same instructions"
    Jev.define :second, "same instructions"
    tape = nil
    Jev.stub(second: 0.9) do
      tape = Jev.record { Jev.record { expect(Jev.feels("hello", :second)).to eq(0.9) } }
    end

    Jev.replay(tape) { expect(Jev.feels("hello", :second)).to eq(0.9) }
  end

  it "takes an independent snapshot of request and response strings" do
    text = +"original"
    winner = +"billing"
    response = {
      "answers" => {
        "support_team" => { "choice" => winner, "confidence" => 1.0, "probabilities" => { "billing" => 1.0 } }
      }
    }
    Jev.configuration.transport = ->(_) { response }
    tape = Jev.record { Jev.decide(text, :support_team) }
    text.replace("changed")
    winner.replace("technical")
    response.clear

    [tape, tape.to_json].each do |recording|
      Jev.replay(recording) { expect(Jev.decide("original", :support_team)).to eq(:billing) }
      Jev.replay(recording) { expect { Jev.decide("changed", :support_team) }.to raise_error(Jev::ReplayError) }
    end
  end

  it "matches requests in any replay order and preserves the first duplicate answer" do
    count = 0
    Jev.configuration.transport = lambda do |_|
      count += 1
      { "answers" => { "feels" => { "noul" => count / 10.0 } } }
    end
    tape = Jev.record do
      Jev.feels("one", :urgent)
      Jev.feels("two", :urgent)
      Jev.feels("one", :urgent)
    end

    [tape, tape.to_json].each do |recording|
      Jev.replay(recording) do
        expect(Jev.feels("two", :urgent)).to eq(0.2)
        expect(Jev.feels("one", :urgent)).to eq(0.1)
        expect(Jev.feels("one", :urgent)).to eq(0.1)
      end
    end
  end

  it "matches equivalent batches independently of question insertion order" do
    Jev.configuration.transport = lambda do |_|
      { "answers" => { "urgent" => { "noul" => 0.9 }, "spam" => { "noul" => 0.1 } } }
    end
    Jev.define :spam, "spam"
    tape = Jev.record do
      Jev.measure("hello") do |q|
        q.feels :urgent
        q.feels :spam
      end
    end

    request = JSON.parse(tape.to_json).fetch("entries").first.fetch("request")
    expect(request.keys).to eq(%w[model questions state])
    expect(request.fetch("questions").keys).to eq(%w[spam urgent])

    Jev.replay(tape.to_json) do
      result = Jev.measure("hello") do |q|
        q.feels :spam
        q.feels :urgent
      end
      expect(result.to_h).to eq(spam: false, urgent: true)
    end
  end

  it "does not expose the stored replay response to mutation" do
    transport = FakeTransport.new(noul: 0.7)
    Jev.configuration.transport = transport
    tape = Jev.record { Jev.feels("hello", :urgent) }
    payload = transport.calls.first
    tape.lookup(payload)["answers"].clear

    Jev.replay(tape) { expect(Jev.feels("hello", :urgent)).to eq(0.7) }
  end

  it "rejects malformed tape entries before replay" do
    expect { Jev.replay({ "entries" => [nil] }) { Jev.feels("hello", :urgent) } }
      .to raise_error(ArgumentError, /invalid entry/)
  end

  it "restores nested stub transports when a block raises" do
    Jev.stub(urgent: 0.2) do
      expect { Jev.stub(urgent: 0.9) { raise "failed" } }.to raise_error("failed")
      expect(Jev.feels("hello", :urgent)).to eq(0.2)
    end
  end
end
