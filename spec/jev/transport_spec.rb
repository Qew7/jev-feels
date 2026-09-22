# frozen_string_literal: true

RSpec.describe Jev::Transport do
  subject(:transport) { described_class.new(config) }

  let(:config) do
    Jev::Configuration.new.tap do |configuration|
      configuration.api_key = "sk-test-secret-key"
    end
  end
  let(:payload) do
    {
      "model" => "jev-latest",
      "state" => "hello",
      "questions" => { "feels" => { "type" => "noul", "instructions" => "urgent" } }
    }
  end
  let(:endpoint) { "https://api.typesafe.ai/v1/systemone" }

  def stub_systemone(status:, body:)
    stub_request(:post, endpoint).to_return(
      status: status,
      body: body,
      headers: { "Content-Type" => "application/json" }
    )
  end

  it "returns a parsed JSON body for a successful response" do
    body = { "answers" => { "feels" => { "type" => "noul", "noul" => 0.91 } } }
    stub_systemone(status: 200, body: JSON.generate(body))

    expect(transport.call(payload)).to eq(body)
    expect(WebMock).to have_requested(:post, endpoint).with(
      headers: {
        "Authorization" => "Bearer sk-test-secret-key",
        "Content-Type" => "application/json"
      }
    )
  end

  it "raises on a malformed JSON success body" do
    stub_systemone(status: 200, body: "{not json")

    expect { transport.call(payload) }.to raise_error(Jev::InvalidResponseError, /not valid JSON/)
  end

  it "raises on authentication failure" do
    stub_systemone(status: 401, body: JSON.generate("error" => "invalid key sk-test-secret-key"))

    expect { transport.call(payload) }.to raise_error(Jev::AuthenticationError, "Jev authentication failed")
  end

  it "raises on rate limit" do
    stub_systemone(status: 429, body: JSON.generate("error" => "slow down"))

    expect { transport.call(payload) }.to raise_error(Jev::RateLimitError, /rate limit/)
  end

  it "wraps a network failure" do
    stub_request(:post, endpoint).to_raise(SocketError.new("getaddrinfo failed"))

    expect { transport.call(payload) }.to raise_error(Jev::RequestError, /request failed/) do |error|
      expect(error.cause).to be_a(SocketError)
    end
  end

  it "wraps a timeout" do
    stub_request(:post, endpoint).to_timeout

    expect { transport.call(payload) }.to raise_error(Jev::RequestError, "Jev request timed out") do |error|
      expect(error.cause).to be_a(Timeout::Error)
    end
  end

  it "never puts the API key in error messages" do
    stub_systemone(status: 422, body: JSON.generate("error" => "rejected key sk-test-secret-key"))

    expect { transport.call(payload) }.to raise_error(Jev::RequestError) do |error|
      expect(error.message).not_to include("sk-test-secret-key")
      expect(error.message).to include("[FILTERED]")
      expect(error.message).not_to include(config.api_key)
    end
  end

  it "raises when the API key is missing" do
    config.api_key = nil

    expect { transport.call(payload) }.to raise_error(Jev::ConfigurationError, "Jev API key is missing")
  end

  ["null", "[]", '"upstream error"', "42", "not json"].each do |body|
    { 401 => Jev::AuthenticationError, 429 => Jev::RateLimitError, 502 => Jev::RequestError }.each do |status, error|
      it "maps HTTP #{status} with #{body.inspect} to #{error}" do
        stub_systemone(status: status, body: body)

        expect { transport.call(payload) }.to raise_error(error)
      end
    end
  end

  it "redacts keys in non-object JSON error bodies" do
    stub_systemone(status: 500, body: JSON.generate([config.api_key]))

    expect { transport.call(payload) }.to raise_error(Jev::RequestError) do |error|
      expect(error.message).to include("[FILTERED]")
      expect(error.message).not_to include(config.api_key)
    end
  end

  it "redacts the whole key before truncating a plain text error" do
    stub_systemone(status: 500, body: ("x" * 195) + config.api_key)

    expect { transport.call(payload) }.to raise_error(Jev::RequestError) do |error|
      expect(error.message).not_to include("sk-te")
      expect(error.message).to end_with("[FILT")
    end
  end

  it "bounds JSON error details after redacting the key" do
    stub_systemone(status: 500, body: JSON.generate("error" => "#{config.api_key}#{'x' * 500}"))

    expect { transport.call(payload) }.to raise_error(Jev::RequestError) do |error|
      expect(error.message).to eq("Jev request failed with HTTP 500: [FILTERED]#{'x' * 190}")
    end
  end
end
