# frozen_string_literal: true

RSpec.describe Jev.const_get(:DefinitionCache) do
  def definition(name = :severity)
    Jev::Definition.build(name: name, instructions: "severity", levels: { low: "minor", high: "major" })
  end

  it "retains compiled fields across garbage collection" do
    item = definition
    cached_id = described_class.fetch(item).object_id
    GC.start(full_mark: true, immediate_sweep: true)

    expect(described_class.fetch(item).object_id).to eq(cached_id)
    expect(item.to_question["criteria"]).to eq(%w[minor major])
  end

  it "evicts old entries while keeping the cache bounded" do
    item = definition
    cached = described_class.fetch(item)
    described_class::LIMIT.times { described_class.fetch(definition) }

    expect(described_class.fetch(item)).not_to equal(cached)
    expect(described_class.fetch(item)).to eq(cached)
    expect(described_class.instance_variable_get(:@fields).size).to eq(described_class::LIMIT)
  end
end
