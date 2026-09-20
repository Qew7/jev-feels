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

  it "scopes the same name to different classes" do
    email = Class.new
    comment = Class.new
    Jev.define email, :urgent, "Outage, customers cannot sign in"
    Jev.define comment, :urgent, "Legal takedown request"

    expect(Jev.definition(email, :urgent)).to eq("Outage, customers cannot sign in")
    expect(Jev.definition(comment, :urgent)).to eq("Legal takedown request")
    expect(Jev.definition(:urgent)).to be_nil
    expect(Jev.definitions(email)).to eq(urgent: "Outage, customers cannot sign in")
    expect { Jev.definitions(email)[:urgent] = "hacked" }.to raise_error(FrozenError)
  end

  it "replaces only the scoped definition" do
    email = Class.new
    Jev.define :urgent, "global"
    Jev.define email, :urgent, "old"
    Jev.define email, :urgent, "new"

    expect(Jev.definition(email, :urgent)).to eq("new")
    expect(Jev.definition(:urgent)).to eq("global")
  end
end
