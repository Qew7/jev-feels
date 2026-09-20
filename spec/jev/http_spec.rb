# frozen_string_literal: true

RSpec.describe "Jev HTTP integration" do
  let(:endpoint) { "https://api.typesafe.ai/v1/systemone" }

  before do
    Jev.configure { |config| config.api_key = "sk-test-secret-key" }
    Jev.define :urgent, "Requires immediate attention or action"
  end

  it "sends a Noul System One request and reads answers.feels.noul" do
    stub_request(:post, endpoint).to_return(
      status: 200,
      body: JSON.generate(
        "model" => "jev-1.13.0",
        "answers" => { "feels" => { "type" => "noul", "noul" => 0.87 } },
        "usage" => { "input_tokens" => 296, "output_tokens" => 20 }
      ),
      headers: { "Content-Type" => "application/json" }
    )

    expect(Jev.feels("Production database is down.", :urgent)).to eq(0.87)

    expect(WebMock).to have_requested(:post, endpoint).with(
      headers: { "Authorization" => "Bearer sk-test-secret-key", "Content-Type" => "application/json" }
    ) { |request|
      json = JSON.parse(request.body)
      json["model"] == "jev-latest" &&
        json["state"] == "Production database is down." &&
        json.dig("questions", "feels", "type") == "noul" &&
        json.dig("questions", "feels", "instructions") == "Requires immediate attention or action"
    }
  end

  it "maps HTTP failures through the public API" do
    stub_request(:post, endpoint).to_return(status: 401, body: "{}")

    expect { Jev.feels?("hello", :urgent) }.to raise_error(Jev::AuthenticationError)
  end
end
