# frozen_string_literal: true

require "spec_helper"
using Jev::Feels

RSpec.describe "String decide / score / measure" do
  before do
    Jev.define :support_team, "Which team?", choices: { billing: "refunds", technical: "bugs" }
    Jev.define :severity, "How severe?", levels: { low: "nudge", high: "down" }
    Jev.configure do |config|
      config.transport = ScriptedTransport.new do |payload|
        id = payload["questions"].keys.first
        type = payload.dig("questions", id, "type")
        case type
        when "choice"
          {
            "answers" => {
              id => {
                "type" => "choice",
                "choice" => "billing",
                "confidence" => 1.0,
                "probabilities" => { "billing" => 1.0, "technical" => 0.0 }
              }
            }
          }
        when "score"
          {
            "answers" => {
              id => { "type" => "score", "score" => 1.0, "confidence" => 1.0,
                      "probabilities" => { "0" => 0.0, "1" => 1.0 } }
            }
          }
        else
          { "answers" => { id => { "type" => "noul", "noul" => 0.9 } } }
        end
      end
    end
  end

  it "adds decide and score on String in this file" do
    expect("charged twice".decide(:support_team)).to eq(:billing)
    expect("cannot pay".score(:severity)).to eq(1.0)
  end

  it "adds measure on String in this file" do
    expect("charged twice".measure(:support_team).choice).to eq(:billing)
  end
end
