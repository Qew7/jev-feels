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
end
