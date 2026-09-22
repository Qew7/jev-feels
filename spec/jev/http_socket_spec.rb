# frozen_string_literal: true

require "socket"

RSpec.describe "HTTP socket lifecycle" do
  around do |example|
    WebMock.disable_net_connect!(allow_localhost: true)
    example.run
  ensure
    WebMock.disable_net_connect!
  end

  before do
    @sockets = []
    @server = TCPServer.new("127.0.0.1", 0)
    @requests = Queue.new
    Jev.define :urgent, "urgent"
    Jev.configuration.api_key = "test-key"
    Jev.configuration.base_url = "http://127.0.0.1:#{@server.addr[1]}"
    Jev.configuration.timeout = 2
  end

  after do
    Jev.reset_configuration!
    @worker&.kill
    @worker&.join
    @sockets.each { |socket| socket.close unless socket.closed? }
    @server&.close
  end

  def serve(*actions)
    @worker = Thread.new do
      socket = nil
      actions.each do |action|
        unless socket
          socket = @server.accept
          @sockets << socket
        end
        @requests << [socket, read_request(socket)]
        write_response(socket, action) unless action == :drop
        next if action == :keep

        socket.close
        socket = nil
      end
    end
  end

  def read_request(socket)
    headers = []
    while (line = socket.gets("\r\n")) && line != "\r\n"
      headers << line
    end
    length = headers.find { |header| header.start_with?("Content-Length:") }.split(":", 2).last.to_i
    JSON.parse(socket.read(length))
  end

  def write_response(socket, action)
    body = JSON.generate("answers" => { "feels" => { "noul" => 0.9 } })
    connection = action == :close ? "close" : "keep-alive"
    socket.write("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\nConnection: #{connection}\r\n\r\n#{body}")
  end

  it "sends consecutive requests over the same TCP connection" do
    serve(:keep, :keep)
    2.times { expect(Jev.feels("hello", :urgent)).to eq(0.9) }
    first, second = Array.new(2) { @requests.pop }

    expect(first.first).to equal(second.first)
    expect(first.last.fetch("state")).to eq("hello")
    expect(@worker.join(2)).not_to be_nil
    @worker.value
  end

  it "opens another socket after the server closes the connection" do
    serve(:close, :keep)
    2.times { expect(Jev.feels("hello", :urgent)).to eq(0.9) }
    first, second = Array.new(2) { @requests.pop }

    expect(first.first).not_to equal(second.first)
    expect(@worker.join(2)).not_to be_nil
    @worker.value
  end

  it "does not retry a dropped POST and recovers on the next call" do
    serve(:drop, :keep)
    expect { Jev.feels("dropped", :urgent) }.to raise_error(Jev::RequestError)
    expect(Jev.feels("next", :urgent)).to eq(0.9)
    first, second = Array.new(2) { @requests.pop }

    expect(first.last.fetch("state")).to eq("dropped")
    expect(second.last.fetch("state")).to eq("next")
    expect(first.first).not_to equal(second.first)
    expect(@worker.join(2)).not_to be_nil
    @worker.value
  end
end
