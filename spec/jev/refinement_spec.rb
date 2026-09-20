# frozen_string_literal: true

require "spec_helper"
using Jev::Feels

RSpec.describe Jev::Feels do
  before do
    Jev.configure { |config| config.transport = FakeTransport.new(noul: 0.94) }
    Jev.define :urgent, "Requires immediate attention or action"
  end

  it "adds feels to String in this file" do
    expect("the server is down".feels(:urgent)).to eq(0.94)
  end

  it "adds feels? to String in this file" do
    expect("the server is down".feels?(:urgent)).to be true
  end

  it "forwards a custom threshold" do
    expect("the server is down".feels?(:urgent, threshold: 0.95)).to be false
  end

  it "accepts an ad-hoc string predicate" do
    expect("please cancel".feels?("sounds like the sender is about to cancel their subscription")).to be true
  end

  it "forwards a scoped predicate" do
    email = Class.new
    Jev.define email, :urgent, "Outage, customers cannot sign in"
    transport = FakeTransport.new(noul: 0.94)
    Jev.configure { |config| config.transport = transport }

    expect("the site is down".feels?(email, :urgent)).to be true
    expect(transport.calls.last.dig("questions", "feels", "instructions"))
      .to eq("Outage, customers cannot sign in")
  end
end
