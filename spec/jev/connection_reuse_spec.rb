# frozen_string_literal: true

RSpec.describe "HTTP connection reuse" do
  let(:endpoint) { "https://api.typesafe.ai/v1/systemone" }
  let(:connections) { [] }

  before do
    Jev.define :urgent, "urgent"
    Jev.configuration.api_key = "test-key"
    stub_request(:post, endpoint).to_return(body: JSON.generate("answers" => { "feels" => { "noul" => 0.9 } }))
    allow(Net::HTTP).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap { |connection| connections << connection }
    end
  end

  after { Jev.reset_configuration! }

  it "reuses a started connection across public API calls" do
    expect(URI).to receive(:join).once.and_call_original
    3.times { expect(Jev.feels("hello", :urgent)).to eq(0.9) }

    expect(connections.size).to eq(1)
    expect(connections.first).to be_started
  end

  it "closes old connections when the base URL changes" do
    Jev.feels("hello", :urgent)
    previous = connections.first
    Jev.configuration.base_url = "https://another.example.test"
    expect(previous).not_to be_started
    stub_request(:post, "https://another.example.test/v1/systemone")
      .to_return(body: JSON.generate("answers" => { "feels" => { "noul" => 0.8 } }))

    expect(Jev.feels("hello", :urgent)).to eq(0.8)
    expect(connections.size).to eq(2)
    expect(connections.last.address).to eq("another.example.test")
  end

  it "observes in-place base URL changes and preserves base paths" do
    Jev.configuration.base_url = +"https://api.typesafe.ai"
    Jev.feels("hello", :urgent)
    Jev.configuration.base_url.replace("https://another.example.test/prefix/")
    stub_request(:post, "https://another.example.test/prefix/v1/systemone")
      .to_return(body: JSON.generate("answers" => { "feels" => { "noul" => 0.8 } }))

    expect(Jev.feels("hello", :urgent)).to eq(0.8)
    expect(connections.first).not_to be_started
  end

  it "closes idle connections when the configuration is reset" do
    Jev.feels("hello", :urgent)
    previous = connections.first
    Jev.reset_configuration!

    expect(previous).not_to be_started
    Jev.configuration.api_key = "new-key"
    expect(Jev.feels("hello", :urgent)).to eq(0.9)
    expect(connections.size).to eq(2)
  end

  it "closes default connections when a custom transport is installed" do
    Jev.feels("hello", :urgent)
    Jev.configuration.transport = FakeTransport.new(noul: 0.2)

    expect(connections.first).not_to be_started
    expect(Jev.feels("hello", :urgent)).to eq(0.2)
    Jev.configuration.transport = nil
    expect(Jev.feels("hello", :urgent)).to eq(0.9)
    expect(connections.size).to eq(2)
  end

  it "updates timeouts and authorization on a reused connection" do
    Jev.feels("hello", :urgent)
    Jev.configuration.timeout = 2.5
    Jev.configuration.api_key = "updated-key"
    Jev.feels("hello", :urgent)

    expect(connections.size).to eq(1)
    expect(connections.first.open_timeout).to eq(2.5)
    expect(connections.first.read_timeout).to eq(2.5)
    expect(connections.first.write_timeout).to eq(2.5)
    expect(WebMock).to have_requested(:post, endpoint).with(headers: { "Authorization" => "Bearer updated-key" }).once
  end

  it "discards a failed connection without retrying the POST" do
    stub_request(:post, endpoint).to_timeout
    expect { Jev.feels("hello", :urgent) }.to raise_error(Jev::RequestError, /timed out/)
    expect(connections.first).not_to be_started
    expect(WebMock).to have_requested(:post, endpoint).once
    stub_request(:post, endpoint).to_return(body: JSON.generate("answers" => { "feels" => { "noul" => 0.7 } }))

    expect(Jev.feels("hello", :urgent)).to eq(0.7)
    expect(connections.size).to eq(2)
  end

  it "does not allocate a connection when the API key is missing" do
    Jev.configuration.api_key = nil

    expect { Jev.feels("hello", :urgent) }.to raise_error(Jev::ConfigurationError)
    expect(connections).to be_empty
  end
end
