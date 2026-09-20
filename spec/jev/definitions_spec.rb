# frozen_string_literal: true

RSpec.describe "Jev definitions" do
  it "stores a definition" do
    Jev.define :urgent, "Requires immediate attention or action"

    expect(Jev.definition(:urgent)).to eq("Requires immediate attention or action")
  end

  it "replaces an existing definition" do
    Jev.define :urgent, "old"
    Jev.define :urgent, "Requires immediate attention or action"

    expect(Jev.definition(:urgent)).to eq("Requires immediate attention or action")
  end

  it "returns nil for an unknown definition" do
    expect(Jev.definition(:missing)).to be_nil
  end

  it "lists definitions without exposing the internal registry" do
    Jev.define :urgent, "Requires immediate attention or action"
    Jev.define :spam, "Unsolicited or unwanted promotional content"

    listed = Jev.definitions
    expect(listed).to eq(
      urgent: "Requires immediate attention or action",
      spam: "Unsolicited or unwanted promotional content"
    )
    expect { listed[:urgent] = "hacked" }.to raise_error(FrozenError)
    expect(Jev.definition(:urgent)).to eq("Requires immediate attention or action")
  end

  it "clears definitions" do
    Jev.define :urgent, "Requires immediate attention or action"
    Jev.reset_definitions!

    expect(Jev.definition(:urgent)).to be_nil
    expect(Jev.definitions).to eq({})
  end

  it "allows concurrent definition writes" do
    threads = Array.new(8) do |i|
      Thread.new do
        50.times { |j| Jev.define(:"k#{i}_#{j}", "d#{i}-#{j}") }
      end
    end
    threads.each(&:join)

    expect(Jev.definitions.size).to eq(400)
  end
end
