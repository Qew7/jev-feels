# frozen_string_literal: true

RSpec.describe "Jev primitives" do
  def answers(map)
    transport = ScriptedTransport.new { |_payload| { "answers" => map } }
    Jev.configure { |config| config.transport = transport }
    transport
  end

  describe "Jev.define" do
    { choices: 255, levels: 10 }.each do |option, maximum|
      it "accepts exactly #{maximum} #{option}" do
        entries = maximum.times.to_h { |index| ["item_#{index}", "Description #{index}"] }
        definition = Jev.define(:limit, "Question", **{ option => entries })

        expect(definition.to_question.fetch("criteria").size).to eq(maximum)
      end

      it "rejects #{option} above the limit for named and ad-hoc questions before transport" do
        entries = (maximum + 1).times.to_h { |index| ["item_#{index}", "Description #{index}"] }
        Jev.configuration.transport = ->(_) { raise "transport must not be called" }
        message = "#{option} must have at most #{maximum} entries"

        expect { Jev.define(:limit, "Question", **{ option => entries }) }.to raise_error(ArgumentError, message)
        expect { Jev.measure("text", "Question", **{ option => entries }) }.to raise_error(ArgumentError, message)
        expect(Jev.definition(:limit)).to be_nil
      end
    end

    it "keeps a plain Noul as a string" do
      Jev.define :urgent, "Requires immediate attention or action"

      expect(Jev.definition(:urgent)).to eq("Requires immediate attention or action")
    end

    it "stores a Choice definition" do
      definition = Jev.define(
        :support_team,
        "Which support team should handle this?",
        choices: {
          billing: "payments, invoices, charges and refunds",
          technical: "bugs, outages and integrations"
        }
      )

      expect(definition.type).to eq(:choice)
      expect(definition.choices).to eq(
        billing: "payments, invoices, charges and refunds",
        technical: "bugs, outages and integrations"
      )
    end

    it "stores named Score levels in Hash order" do
      definition = Jev.define(
        :severity,
        "How severe is this customer issue?",
        levels: {
          cosmetic: "minor visual or cosmetic issue",
          degraded: "functionality is degraded but a workaround exists",
          blocking: "the customer cannot complete an important task",
          critical: "major outage, data loss, security issue, or severe business impact"
        }
      )

      expect(definition.type).to eq(:score)
      expect(definition.level_names).to eq(%i[cosmetic degraded blocking critical])
    end

    it "rejects a Score levels array" do
      expect do
        Jev.define :severity, "How severe?", levels: %w[low high]
      end.to raise_error(ArgumentError, "levels must be a Hash")
    end

    it "rejects choices and levels together" do
      expect do
        Jev.define :mixed, "x", choices: { a: "a" }, levels: { low: "a", high: "b" }
      end.to raise_error(ArgumentError, "cannot use choices: and levels: together")
    end

    it "rejects an empty Choice" do
      expect do
        Jev.define :team, "Which team?", choices: {}
      end.to raise_error(ArgumentError, "choices cannot be empty")
    end

    it "rejects too few Score levels" do
      expect do
        Jev.define :severity, "How severe?", levels: { only: "one" }
      end.to raise_error(ArgumentError, "levels must have at least 2 entries")
    end

    it "rejects duplicate Choice keys" do
      expect do
        Jev.define :team, "Which team?", choices: { billing: "a", "billing" => "b" }
      end.to raise_error(ArgumentError, "duplicate choice key: :billing")
    end

    it "rejects invalid keys" do
      expect do
        Jev.define :team, "Which team?", choices: { "" => "x", other: "y" }
      end.to raise_error(ArgumentError, /invalid choice key/)
    end
  end

  describe "request serialization" do
    it "sends a Choice question" do
      Jev.define :support_team, "Which team?", choices: { billing: "refunds", technical: "bugs" }
      transport = answers(
        "support_team" => {
          "type" => "choice",
          "choice" => "billing",
          "confidence" => 0.91,
          "probabilities" => { "billing" => 0.91, "technical" => 0.09 }
        }
      )

      expect(Jev.decide("I was charged twice", :support_team)).to eq(:billing)
      expect(transport.calls.first).to eq(
        "model" => "jev-latest",
        "state" => "I was charged twice",
        "questions" => {
          "support_team" => {
            "type" => "choice",
            "instructions" => "Which team?",
            "criteria" => { "billing" => "refunds", "technical" => "bugs" }
          }
        }
      )
    end

    it "sends Score levels as an ordered criteria array" do
      Jev.define :severity, "How severe?", levels: { cosmetic: "visual", blocking: "cannot finish" }
      transport = answers(
        "severity" => {
          "type" => "score",
          "score" => 0.4,
          "confidence" => 0.7,
          "probabilities" => { "0" => 0.6, "1" => 0.4 }
        }
      )

      expect(Jev.score("button is misaligned", :severity)).to eq(0.4)
      expect(transport.calls.first.dig("questions", "severity")).to eq(
        "type" => "score",
        "instructions" => "How severe?",
        "criteria" => ["visual", "cannot finish"]
      )
    end
  end

  describe "response parsing" do
    before do
      Jev.define :support_team, "Which team?", choices: { billing: "refunds", technical: "bugs" }
      Jev.define :severity, "How severe?", levels: { cosmetic: "visual", blocking: "stuck" }
    end

    it "parses a Choice winner, confidence, and probabilities" do
      answers(
        "support_team" => {
          "type" => "choice",
          "choice" => "technical",
          "confidence" => 0.64,
          "probabilities" => { "billing" => 0.2, "technical" => 0.8 }
        }
      )

      result = Jev.measure("the API is down", :support_team)
      expect(result).to be_a(Jev::Result::Choice)
      expect(result.choice).to eq(:technical)
      expect(result.confidence).to eq(0.64)
      expect(result.probabilities).to eq(billing: 0.2, technical: 0.8)
      expect(result.type).to eq(:choice)
    end

    it "parses a Score without turning it into a percentage" do
      Jev.define :severity, "How severe?", levels: {
        cosmetic: "visual",
        degraded: "workaround",
        blocking: "stuck",
        critical: "outage"
      }
      answers(
        "severity" => {
          "type" => "score",
          "score" => 2.37,
          "confidence" => 0.55,
          "probabilities" => { "0" => 0.05, "1" => 0.15, "2" => 0.7, "3" => 0.1 }
        }
      )

      result = Jev.measure("cannot complete checkout", :severity)
      expect(result.score).to eq(2.37)
      expect(result.confidence).to eq(0.55)
      expect(result.level).to eq(:blocking)
      expect(result.levels.keys).to eq(%i[cosmetic degraded blocking critical])
      expect(result.type).to eq(:score)
    end

    it "raises when a Choice answer is missing" do
      Jev.configure { |config| config.transport = ->(_payload) { { "answers" => {} } } }

      expect { Jev.decide("x", :support_team) }.to raise_error(Jev::InvalidResponseError, /missing the support_team/)
    end
  end

  describe "Jev.decide / Jev.score" do
    it "returns nil when Choice confidence is below the floor" do
      Jev.define :support_team, "Which team?", choices: { billing: "refunds", technical: "bugs" }
      answers(
        "support_team" => {
          "type" => "choice",
          "choice" => "billing",
          "confidence" => 0.4,
          "probabilities" => { "billing" => 0.55, "technical" => 0.45 }
        }
      )

      expect(Jev.decide("maybe a refund", :support_team, confidence: 0.8)).to be_nil
      expect(Jev.decide("maybe a refund", :support_team)).to eq(:billing)
    end

    it "does not treat winner probability as confidence" do
      Jev.define :support_team, "Which team?", choices: { billing: "refunds", technical: "bugs" }
      answers(
        "support_team" => {
          "type" => "choice",
          "choice" => "billing",
          "confidence" => 0.3,
          "probabilities" => { "billing" => 0.9, "technical" => 0.1 }
        }
      )

      expect(Jev.decide("charged twice", :support_team, confidence: 0.8)).to be_nil
    end

    it "accepts an ad-hoc Choice" do
      transport = answers(
        "choice" => {
          "type" => "choice",
          "choice" => "billing",
          "confidence" => 1.0,
          "probabilities" => { "billing" => 1.0, "other" => 0.0 }
        }
      )

      expect(
        Jev.decide(
          "refund please",
          "Which support team should handle this?",
          choices: { billing: "refunds", other: "none of the above" }
        )
      ).to eq(:billing)
      expect(transport.calls.first.dig("questions", "choice", "type")).to eq("choice")
      expect(Jev.definitions).to eq({})
    end

    it "accepts an ad-hoc Score" do
      answers(
        "score" => {
          "type" => "score",
          "score" => 1.2,
          "confidence" => 0.8,
          "probabilities" => { "0" => 0.2, "1" => 0.6, "2" => 0.2 }
        }
      )

      expect(Jev.score("it hurts", "How severe?", levels: { low: "nudge", mid: "hurt", high: "down" })).to eq(1.2)
    end

    it "requires choices for an ad-hoc Choice" do
      expect { Jev.decide("x", "Which team?") }.to raise_error(ArgumentError, "choices is required")
    end

    it "rejects an invalid confidence" do
      Jev.define :support_team, "Which team?", choices: { billing: "refunds", technical: "bugs" }

      expect do
        Jev.decide("x", :support_team, confidence: 1.5)
      end.to raise_error(ArgumentError, "confidence must be a Float between 0.0 and 1.0")
    end

    it "raises UndefinedDefinition for an unknown symbol" do
      expect { Jev.decide("x", :missing) }.to raise_error(Jev::UndefinedDefinition)
    end
  end

  it "checks single-question types before invoking the transport" do
    Jev.define :urgent, "urgent"
    Jev.define :team, "team", choices: { a: "a" }
    Jev.define :severity, "severity", levels: { low: "low", high: "high" }
    transport = instance_double(Jev::Transport)
    Jev.configuration.transport = transport
    expect(transport).not_to receive(:call)

    expect { Jev.decide("hello", :urgent) }.to raise_error(ArgumentError, /not a choice/)
    expect { Jev.score("hello", :team) }.to raise_error(ArgumentError, /not a score/)
    expect { Jev.feels("hello", :severity) }.to raise_error(ArgumentError, /not a noul/)
    expect { Jev.feels?("hello", :team) }.to raise_error(ArgumentError, /not a noul/)
  end

  it "preserves mutable public definition views without exposing cached criteria" do
    choice = Jev.define :team, "team", choices: { billing: "refunds" }
    score = Jev.define :severity, "severity", levels: { low: "minor", high: "major" }
    choice.to_question["criteria"].clear
    choice.to_question["type"].replace("changed")
    score.to_question["criteria"].clear
    score.level_names.clear
    score.level_descriptions.clear

    expect(choice.to_question).to eq("type" => "choice", "instructions" => "team",
                                     "criteria" => { "billing" => "refunds" })
    expect(score.to_question["criteria"]).to eq(%w[minor major])
    expect(score.level_names).to eq(%i[low high])
    expect(score.level_descriptions).to eq(%w[minor major])
  end

  it "preserves Data copying and Marshal round-trips after warming the definition cache" do
    definition = Jev.define :severity, "severity", levels: { low: "minor", high: "major" }
    definition.to_question
    copied = definition.with(levels: { first: "one", second: "two" })

    expect(copied.level_names).to eq(%i[first second])
    expect(copied.to_question["criteria"]).to eq(%w[one two])
    restored = Marshal.load(Marshal.dump(definition))
    expect(restored).to eq(definition)
    expect(restored.to_question).to eq(definition.to_question)
  end

  it "keeps directly constructed definitions responsive to mutable criteria" do
    levels = { low: "minor", high: "major" }
    definition = Jev::Definition.new(name: :severity, type: :score, instructions: "severity", choices: nil,
                                     levels: levels)
    definition.to_question
    levels[:critical] = "critical"

    expect(definition.level_names).to eq(%i[low high critical])
    expect(definition.to_question["criteria"]).to eq(%w[minor major critical])
  end
end
