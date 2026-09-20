# frozen_string_literal: true

RSpec.describe "uncertainty" do
  before do
    Jev.define :urgent, "Requires immediate attention or action"
  end

  def stub_noul(noul)
    Jev.configure { |config| config.transport = FakeTransport.new(noul: noul) }
  end

  it "keeps feels? boolean without at_least" do
    stub_noul(0.51)

    expect(Jev.feels?("maybe urgent", :urgent)).to be true
  end

  it "returns a tri-state with at_least" do
    stub_noul(0.81)
    expect(Jev.feels?("act now", :urgent, at_least: 0.8)).to be true

    stub_noul(0.2)
    expect(Jev.feels?("whenever", :urgent, at_least: 0.8)).to be false

    stub_noul(0.5)
    expect(Jev.feels?("unclear", :urgent, at_least: 0.8)).to be_nil
  end

  it "does not mix threshold and at_least" do
    stub_noul(0.9)

    expect do
      Jev.feels?("x", :urgent, threshold: 0.6, at_least: 0.8)
    end.to raise_error(ArgumentError, "cannot use threshold: and at_least: together")
  end

  it "rejects an invalid at_least" do
    stub_noul(0.9)

    expect { Jev.feels?("x", :urgent, at_least: 1.2) }.to raise_error(
      ArgumentError, "at_least must be a Float between 0.0 and 1.0"
    )
  end

  it "still uses threshold as a single cut" do
    stub_noul(0.79)

    expect(Jev.feels?("x", :urgent, threshold: 0.8)).to be false
    expect(Jev.feels?("x", :urgent, threshold: 0.79)).to be true
  end
end
