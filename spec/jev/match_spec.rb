# frozen_string_literal: true

RSpec.describe "Jev.match" do
  before do
    Jev.define :support_team, "Which team?", choices: {
      billing: "refunds",
      technical: "bugs",
      sales: "pricing"
    }
  end

  def stub_choice(winner, confidence: 1.0)
    Jev.configure do |config|
      config.transport = lambda { |_payload|
        {
          "answers" => {
            "support_team" => {
              "type" => "choice",
              "choice" => winner.to_s,
              "confidence" => confidence,
              "probabilities" => { winner.to_s => 1.0 }
            }
          }
        }
      }
    end
  end

  it "dispatches the winning branch" do
    stub_choice(:billing)
    routed = Jev.match("charged twice", :support_team) do
      on(:billing) { :billing }
      on(:technical) { :technical }
      otherwise { :manual }
    end

    expect(routed).to eq(:billing)
  end

  it "accepts several values on one branch" do
    stub_choice(:sales)
    routed = Jev.match("what does pro cost", :support_team) do
      on(:billing, :sales) { :commercial }
      otherwise { :manual }
    end

    expect(routed).to eq(:commercial)
  end

  it "sends low confidence to otherwise" do
    stub_choice(:billing, confidence: 0.4)
    routed = Jev.match("maybe a charge", :support_team, confidence: 0.8) do
      on(:billing) { :billing }
      otherwise { :manual }
    end

    expect(routed).to eq(:manual)
  end
end
