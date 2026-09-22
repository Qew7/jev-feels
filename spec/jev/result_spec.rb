# frozen_string_literal: true

RSpec.describe Jev::Result do
  let(:choice) { Jev.define :team, "Which team?", choices: { billing: "refunds", technical: "bugs" } }
  let(:score) { Jev.define :severity, "How severe?", levels: { low: "minor", high: "major" } }
  let(:choice_answer) do
    { "choice" => "billing", "confidence" => 0.8, "probabilities" => { "billing" => 0.8, "technical" => 0.2 } }
  end
  let(:score_answer) { { "score" => 0.8, "confidence" => 0.9, "probabilities" => { "0" => 0.2, "1" => 0.8 } } }

  [nil, 1, false, [], {}].each do |winner|
    it "rejects a malformed Choice winner #{winner.inspect} with a gem error" do
      expect { described_class.parse(choice_answer.merge("choice" => winner), choice) }
        .to raise_error(Jev::InvalidResponseError)
    end
  end

  it "rejects a winner outside the declared choices" do
    expect { described_class.parse(choice_answer.merge("choice" => "unknown"), choice) }
      .to raise_error(Jev::InvalidResponseError, /unknown choice/)
  end

  [1, nil, "unknown"].each do |key|
    it "rejects an invalid Choice probability key #{key.inspect}" do
      expect { described_class.parse(choice_answer.merge("probabilities" => { key => 1.0 }), choice) }
        .to raise_error(Jev::InvalidResponseError)
    end
  end

  ["-1", -1, "2", 2, "1.0", 0.5, nil, "junk"].each do |key|
    it "rejects an invalid Score probability index #{key.inspect}" do
      expect { described_class.parse(score_answer.merge("probabilities" => { key => 1.0 }), score) }
        .to raise_error(Jev::InvalidResponseError)
    end
  end

  it "supports integer level indexes from custom transports" do
    result = described_class.parse(score_answer.merge("probabilities" => { 0 => 0.2, 1 => 0.8 }), score)

    expect(result.probabilities).to eq(low: 0.2, high: 0.8)
    expect(result.level).to eq(:high)
  end

  it "reads level indexes as decimal numbers" do
    levels = 10.times.to_h { |index| ["level_#{index}", index.to_s] }
    definition = Jev.define :decimal, "severity", levels: levels
    result = described_class.parse(score_answer.merge("probabilities" => { "08" => 1.0 }), definition)

    expect(result.level.to_s).to eq("level_8")
  end

  it "collapses only requested keys for pattern matching" do
    urgent = Jev::Result::Noul.new(probability: 0.9)
    other = instance_double(Jev::Result::Noul)
    batch = Jev::Result::Batch.new(urgent: urgent, other: other)
    expect(other).not_to receive(:collapsed)

    expect(batch.deconstruct_keys(["urgent", :missing])).to eq(urgent: true)
  end

  it "returns independent mutable hashes when deconstructing all keys" do
    batch = Jev::Result::Batch.new(urgent: Jev::Result::Noul.new(probability: 0.9))
    batch.deconstruct_keys(nil).clear
    batch.to_h.clear

    expect(batch.deconstruct_keys(nil)).to eq(urgent: true)
    expect(batch.deconstruct_keys([])).to eq({})
  end

  [nil, "0.5", Float::NAN, Float::INFINITY, Complex(1, 1)].each do |value|
    it "rejects invalid numeric result fields #{value.inspect} with gem errors" do
      expect { described_class.parse(choice_answer.merge("confidence" => value), choice) }
        .to raise_error(Jev::InvalidResponseError)
      expect { described_class.parse(choice_answer.merge("probabilities" => { "billing" => value }), choice) }
        .to raise_error(Jev::InvalidResponseError)
      expect { described_class.parse(score_answer.merge("score" => value), score) }
        .to raise_error(Jev::InvalidResponseError)
      expect { described_class.parse(score_answer.merge("confidence" => value), score) }
        .to raise_error(Jev::InvalidResponseError)
      expect { described_class.parse(score_answer.merge("probabilities" => { "0" => value }), score) }
        .to raise_error(Jev::InvalidResponseError)
    end
  end

  it "preserves the standalone Choice parser and Symbol keys from custom transports" do
    result = Jev::Result::Choice.parse("choice" => :billing, "confidence" => 1.0, "probabilities" => { billing: 1.0 })

    expect(result.choice).to eq(:billing)
    expect(result.probabilities).to eq(billing: 1.0)
  end
end
