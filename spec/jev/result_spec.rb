# frozen_string_literal: true

RSpec.describe Jev::Result do
  let(:choice) { Jev.define :team, "Which team?", choices: { billing: "refunds", technical: "bugs" } }
  let(:score) { Jev.define :severity, "How severe?", levels: { low: "minor", high: "major" } }
  let(:choice_answer) do
    { "choice" => "billing", "confidence" => 0.8, "probabilities" => { "billing" => 0.8, "technical" => 0.2 } }
  end
  let(:score_answer) { { "score" => 0.8, "confidence" => 0.9, "probabilities" => { "0" => 0.2, "1" => 0.8 } } }

  it "rejects a winner outside the declared choices" do
    expect { described_class.parse(choice_answer.merge("choice" => "unknown"), choice) }
      .to raise_error(Jev::InvalidResponseError, /unknown choice/)
  end

  it "rejects a score probability for an unknown level" do
    expect { described_class.parse(score_answer.merge("probabilities" => { "2" => 1.0 }), score) }
      .to raise_error(Jev::InvalidResponseError, /unknown level/)
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
end
