# frozen_string_literal: true

RSpec.describe "Jev HTTP integration" do
  let(:endpoint) { "https://api.typesafe.ai/v1/systemone" }

  before do
    Jev.configure { |config| config.api_key = "sk-test-secret-key" }
    Jev.define :urgent, "Requires immediate attention or action"
  end

  it "returns noul through the public API" do
    stub_request(:post, endpoint).to_return(
      status: 200,
      body: JSON.generate("answers" => { "feels" => { "type" => "noul", "noul" => 0.87 } }),
      headers: { "Content-Type" => "application/json" }
    )

    expect(Jev.feels("Production database is down.", :urgent)).to eq(0.87)
    expect(Jev.feels?("Production database is down.", :urgent)).to be true
  end

  it "maps HTTP failures through the public API" do
    stub_request(:post, endpoint).to_return(status: 401, body: "{}")

    expect { Jev.feels?("hello", :urgent) }.to raise_error(Jev::AuthenticationError)
  end
end
